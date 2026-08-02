//
//  ResizeHEIC.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers


enum HEICResizeError: LocalizedError {
	case invalidScale(CGFloat)
	case invalidCompressionQuality(Double)
	case couldNotOpenSource
	case couldNotCreateDestination
	case missingImageDimensions
	case couldNotLoadMainImage
	case couldNotCreatePQColorSpace
	case couldNotCreateSDRColorSpace
	case couldNotWriteImage
	case couldNotLoadAuxiliaryImage(AuxiliaryMapKind)

	var errorDescription: String? {
		switch self {
		case .invalidScale(let scale):
			return "Invalid image scale: \(scale)."

		case .invalidCompressionQuality(let quality):
			return "Invalid compression quality: \(quality)."

		case .couldNotOpenSource:
			return "Could not open the source HEIC image."

		case .couldNotCreateDestination:
			return "Could not create the destination HEIC image."

		case .missingImageDimensions:
			return "Could not read the source image dimensions."

		case .couldNotLoadMainImage:
			return "Core Image could not load the main image."

		case .couldNotCreatePQColorSpace:
			return "Could not create the BT.2100 PQ color space."

		case .couldNotCreateSDRColorSpace:
			return "Could not create the Display P3 color space."

		case .couldNotWriteImage:
			return "Core Image could not write the output HEIC."

		case .couldNotLoadAuxiliaryImage(let kind):
			return "Core Image could not load the \(kind.displayName)."
		}
	}
}


func resizeHEIC(
	from inputURL: URL,
	to outputURL: URL,
	scale: CGFloat,
	compressionQuality: Double,
	auxiliaryOptions: [AuxiliaryMapOption],
	previewDirectory: URL
) throws -> HEICResizeResult {

	guard scale > 0, scale <= 1 else {
		throw HEICResizeError.invalidScale(scale)
	}

	guard (0...1).contains(compressionQuality) else {
		throw HEICResizeError.invalidCompressionQuality(
			compressionQuality
		)
	}

	try FileManager.default.createDirectory(
		at: previewDirectory,
		withIntermediateDirectories: true
	)

	guard let imageSource = CGImageSourceCreateWithURL(
		inputURL as CFURL,
		nil
	) else {
		throw HEICResizeError.couldNotOpenSource
	}

	let imageIndex = 0

	guard
		let imageProperties =
			CGImageSourceCopyPropertiesAtIndex(
				imageSource,
				imageIndex,
				nil
			) as? [CFString: Any],
		let width = integerValue(
			imageProperties[
				kCGImagePropertyPixelWidth
			]
		),
		let height = integerValue(
			imageProperties[
				kCGImagePropertyPixelHeight
			]
		)
	else {
		throw HEICResizeError.missingImageDimensions
	}

	let originalDimensions = PixelDimensions(
		width: width,
		height: height
	)

	let sourceHasGainMap =
		CGImageSourceCopyAuxiliaryDataInfoAtIndex(
			imageSource,
			imageIndex,
			kCGImageAuxiliaryDataTypeHDRGainMap
		) != nil

	let context = CIContext()

	/*
	 Gain-map images must remain an SDR base plus a gain map.

	 Native HDR images are loaded expanded into their HDR representation
	 and written as 10-bit BT.2100 PQ.
	 */
	let mainLoadOptions: [CIImageOption: Any]

	if sourceHasGainMap {
		mainLoadOptions = [
			.applyOrientationProperty: true
		]
	} else {
		mainLoadOptions = [
			.applyOrientationProperty: true,
			.expandToHDR: true
		]
	}

	guard var sourceImage = CIImage(
		contentsOf: inputURL,
		options: mainLoadOptions
	) else {
		throw HEICResizeError.couldNotLoadMainImage
	}

	sourceImage = normalizeOrigin(sourceImage)

	let resizedMainImage = resizeCIImage(
		sourceImage,
		scale: scale
	)

	let outputDimensions = PixelDimensions(
		width: Int(resizedMainImage.extent.width.rounded()),
		height: Int(resizedMainImage.extent.height.rounded())
	)

	var representationOptions:
		[CIImageRepresentationOption: Any] = [:]

	let qualityOption = CIImageRepresentationOption(
		rawValue:
			kCGImageDestinationLossyCompressionQuality
				as String
	)

	representationOptions[qualityOption] =
		compressionQuality

	var auxiliaryResults:
		[AuxiliaryMapKind: AuxiliaryMapResult] = [:]

	for option in auxiliaryOptions {
		let result = try processAuxiliaryImage(
			option,
			from: inputURL,
			imageSource: imageSource,
			imageIndex: imageIndex,
			context: context,
			previewDirectory: previewDirectory,
			representationOptions:
				&representationOptions
		)

		auxiliaryResults[option.kind] = result
	}

	if FileManager.default.fileExists(
		atPath: outputURL.path
	) {
		try FileManager.default.removeItem(
			at: outputURL
		)
	}

	if sourceHasGainMap {
		guard let displayP3 = CGColorSpace(
			name: CGColorSpace.displayP3
		) else {
			throw HEICResizeError
				.couldNotCreateSDRColorSpace
		}

		/*
		 Keep the SDR base as an 8-bit Display P3 image. The separately
		 attached gain map restores the HDR presentation.
		 */
		try context.writeHEIFRepresentation(
			of: resizedMainImage,
			to: outputURL,
			format: .RGBA8,
			colorSpace: displayP3,
			options: representationOptions
		)

	} else {
		guard let pqColorSpace = CGColorSpace(
			name: CGColorSpace.itur_2100_PQ
		) else {
			throw HEICResizeError
				.couldNotCreatePQColorSpace
		}

		/*
		 Native HDR path. This is the path that preserved the highlight
		 detail in the command-line experiment.
		 */
		try context.writeHEIF10Representation(
			of: resizedMainImage,
			to: outputURL,
			colorSpace: pqColorSpace,
			options: representationOptions
		)
	}

	return HEICResizeResult(
		fileName: inputURL.lastPathComponent,
		mainImageOriginal: originalDimensions,
		mainImageOutput: outputDimensions,
		mainImagePreview: ImagePreview(
			url: outputURL
		),
		auxiliaryResults: auxiliaryResults
	)
}


// MARK: - Auxiliary processing

private func processAuxiliaryImage(
	_ option: AuxiliaryMapOption,
	from inputURL: URL,
	imageSource: CGImageSource,
	imageIndex: Int,
	context: CIContext,
	previewDirectory: URL,
	representationOptions:
		inout [CIImageRepresentationOption: Any]
) throws -> AuxiliaryMapResult {

	let imageIOType = option.kind.imageIOType

	guard let auxiliaryInfo =
		CGImageSourceCopyAuxiliaryDataInfoAtIndex(
			imageSource,
			imageIndex,
			imageIOType
		)
	else {
		return .absent
	}

	let originalDimensions =
		auxiliaryDimensions(from: auxiliaryInfo)
		?? PixelDimensions(
			width: 0,
			height: 0
		)

	guard option.isEnabled else {
		print(
			"Discarded \(option.kind.displayName)"
		)

		return .discarded(
			original: originalDimensions
		)
	}

	guard var auxiliaryImage = loadAuxiliaryCIImage(
		option.kind,
		from: inputURL
	) else {
		throw HEICResizeError
			.couldNotLoadAuxiliaryImage(option.kind)
	}

	/*
	 Preserve the auxiliary image's metadata. Gain-map metadata in
	 particular describes how the map should be interpreted.
	 */
	let originalProperties =
		auxiliaryImage.properties

	auxiliaryImage =
		normalizeOrigin(auxiliaryImage)

	let resizedAuxiliaryImage = resizeCIImage(
		auxiliaryImage,
		scale: option.scale
	)
	.settingProperties(originalProperties)

	let outputDimensions = PixelDimensions(
		width: Int(
			resizedAuxiliaryImage.extent.width.rounded()
		),
		height: Int(
			resizedAuxiliaryImage.extent.height.rounded()
		)
	)

	representationOptions[
		option.kind.coreImageRepresentationOption
	] = resizedAuxiliaryImage

	let previewURL = previewDirectory
		.appendingPathComponent(
			"\(option.kind.rawValue).png"
		)

	let preview = createAuxiliaryPreview(
		from: resizedAuxiliaryImage,
		context: context,
		at: previewURL
	)

	print(
		"""
		Resized \(option.kind.displayName): \
		\(originalDimensions.description) → \
		\(outputDimensions.description)
		"""
	)

	return .resized(
		original: originalDimensions,
		output: outputDimensions,
		preview: preview
	)
}


// MARK: - Core Image auxiliary loading

private func loadAuxiliaryCIImage(
	_ kind: AuxiliaryMapKind,
	from inputURL: URL
) -> CIImage? {

	let options: [CIImageOption: Any] = [
		kind.coreImageLoadOption: true,
		.applyOrientationProperty: true
	]

	return CIImage(
		contentsOf: inputURL,
		options: options
	)
}


private extension AuxiliaryMapKind {

	var coreImageLoadOption: CIImageOption {
		switch self {
		case .hdrGainMap:
			return .auxiliaryHDRGainMap

		case .depth:
			return .auxiliaryDepth

		case .disparity:
			return .auxiliaryDisparity

		case .portraitEffectsMatte:
			return .auxiliaryPortraitEffectsMatte
		}
	}


	var coreImageRepresentationOption:
		CIImageRepresentationOption {

		switch self {
		case .hdrGainMap:
			return .hdrGainMapImage

		case .depth:
			return .depthImage

		case .disparity:
			return .disparityImage

		case .portraitEffectsMatte:
			return .portraitEffectsMatteImage
		}
	}
}


// MARK: - Core Image scaling

private func resizeCIImage(
	_ image: CIImage,
	scale: CGFloat
) -> CIImage {

	/*
	 At 100%, leave the CIImage graph untouched. It will still be encoded
	 again, but no resampling filter is applied.
	 */
	guard abs(scale - 1) > 0.000_001 else {
		return image
	}

	let scaled = image.applyingFilter(
		"CILanczosScaleTransform",
		parameters: [
			kCIInputScaleKey: scale,
			kCIInputAspectRatioKey: 1.0
		]
	)

	let normalized = normalizeOrigin(scaled)

	let outputWidth = max(
		1,
		Int(
			(image.extent.width * scale)
				.rounded()
		)
	)

	let outputHeight = max(
		1,
		Int(
			(image.extent.height * scale)
				.rounded()
		)
	)

	return normalized.cropped(
		to: CGRect(
			x: 0,
			y: 0,
			width: outputWidth,
			height: outputHeight
		)
	)
}


private func normalizeOrigin(
	_ image: CIImage
) -> CIImage {

	guard
		image.extent.origin.x != 0
		|| image.extent.origin.y != 0
	else {
		return image
	}

	return image.transformed(
		by: CGAffineTransform(
			translationX: -image.extent.origin.x,
			y: -image.extent.origin.y
		)
	)
}


// MARK: - Auxiliary previews

private func createAuxiliaryPreview(
	from image: CIImage,
	context: CIContext,
	at outputURL: URL
) -> ImagePreview {

	do {
		let previewImage = normalizePreviewImage(
			image,
			context: context
		)

		if FileManager.default.fileExists(
			atPath: outputURL.path
		) {
			try FileManager.default.removeItem(
				at: outputURL
			)
		}

		try context.writePNGRepresentation(
			of: previewImage,
			to: outputURL,
			format: .L8,
			colorSpace:
				CGColorSpaceCreateDeviceGray(),
			options: [:]
		)

		return ImagePreview(
			url: outputURL
		)

	} catch {
		print(
			"""
			Warning: could not create auxiliary preview \
			\(outputURL.lastPathComponent): \
			\(error.localizedDescription)
			"""
		)

		return ImagePreview(url: nil)
	}
}


/*
 CI auxiliary images can be integer, floating-point, or encoded using a
 specialized range. CIAreaMinMax finds their actual range, then CIColorMatrix
 maps that range to visible black-to-white for the PNG preview.
 */
private func normalizePreviewImage(
	_ image: CIImage,
	context: CIContext
) -> CIImage {

	guard
		let minimumAndMaximum =
			previewMinimumAndMaximum(
				of: image,
				context: context
			)
	else {
		return image
	}

	let minimum = minimumAndMaximum.minimum
	let maximum = minimumAndMaximum.maximum
	let range = maximum - minimum

	guard
		range.isFinite,
		range > Float.ulpOfOne
	else {
		return image
	}

	let multiplier = CGFloat(1 / range)
	let bias = CGFloat(-minimum / range)

	return image.applyingFilter(
		"CIColorMatrix",
		parameters: [
			"inputRVector":
				CIVector(
					x: multiplier,
					y: 0,
					z: 0,
					w: 0
				),
			"inputGVector":
				CIVector(
					x: multiplier,
					y: 0,
					z: 0,
					w: 0
				),
			"inputBVector":
				CIVector(
					x: multiplier,
					y: 0,
					z: 0,
					w: 0
				),
			"inputBiasVector":
				CIVector(
					x: bias,
					y: bias,
					z: bias,
					w: 0
				)
		]
	)
}


private func previewMinimumAndMaximum(
	of image: CIImage,
	context: CIContext
) -> (
	minimum: Float,
	maximum: Float
)? {

	let extent = image.extent.integral

	guard !extent.isEmpty else {
		return nil
	}

	let minMaxImage = image.applyingFilter(
		"CIAreaMinMax",
		parameters: [
			kCIInputExtentKey:
				CIVector(cgRect: extent)
		]
	)

	var pixels = [
		Float
	](
		repeating: 0,
		count: 8
	)

	context.render(
		minMaxImage,
		toBitmap: &pixels,
		rowBytes:
			MemoryLayout<Float>.size * 8,
		bounds: CGRect(
			x: 0,
			y: 0,
			width: 2,
			height: 1
		),
		format: .Rf,
		colorSpace: nil
	)

	return (
		minimum: pixels[0],
		maximum: pixels[1]
	)
}


// MARK: - Value parsing

private func integerValue(
	_ value: Any?
) -> Int? {

	if let value = value as? Int {
		return value
	}

	if let value = value as? NSNumber {
		return value.intValue
	}

	return nil
}
