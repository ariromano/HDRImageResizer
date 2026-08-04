//
//  ResizeHEIC.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers


enum HEICResizeError: LocalizedError {
	case invalidScale(CGFloat)
	case invalidCompressionQuality(Double)
	case couldNotOpenSource
	case couldNotCreateDestination
	case missingImageDimensions
	case couldNotCreateThumbnail
	case couldNotFinalizeDestination

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

		case .couldNotCreateThumbnail:
			return "Could not create the resized image."

		case .couldNotFinalizeDestination:
			return "Could not finish writing the resized HEIC image."
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

	guard let source = CGImageSourceCreateWithURL(
		inputURL as CFURL,
		nil
	) else {
		throw HEICResizeError.couldNotOpenSource
	}

	guard let destination = CGImageDestinationCreateWithURL(
		outputURL as CFURL,
		UTType.heic.identifier as CFString,
		1,
		nil
	) else {
		throw HEICResizeError.couldNotCreateDestination
	}

	let imageIndex = 0

	guard
		let properties = CGImageSourceCopyPropertiesAtIndex(
			source,
			imageIndex,
			nil
		) as? [CFString: Any],
		let width = integerValue(
			properties[kCGImagePropertyPixelWidth]
		),
		let height = integerValue(
			properties[kCGImagePropertyPixelHeight]
		)
	else {
		throw HEICResizeError.missingImageDimensions
	}

	let originalDimensions = PixelDimensions(
		width: width,
		height: height
	)

	let maximumPixelSize = max(
		1,
		Int(
			(CGFloat(max(width, height)) * scale)
				.rounded()
		)
	)

	let thumbnailOptions: [CFString: Any] = [
		kCGImageSourceCreateThumbnailFromImageAlways: true,
		kCGImageSourceThumbnailMaxPixelSize:
			maximumPixelSize,
		kCGImageSourceCreateThumbnailWithTransform:
			false
	]

	guard let resizedImage =
		CGImageSourceCreateThumbnailAtIndex(
			source,
			imageIndex,
			thumbnailOptions as CFDictionary
		)
	else {
		throw HEICResizeError.couldNotCreateThumbnail
	}

	let outputDimensions = PixelDimensions(
		width: resizedImage.width,
		height: resizedImage.height
	)

	var outputProperties = properties

	outputProperties[kCGImagePropertyPixelWidth] =
		resizedImage.width

	outputProperties[kCGImagePropertyPixelHeight] =
		resizedImage.height

	// Preserving orientation metadata instead of baking

	outputProperties[
		kCGImageDestinationLossyCompressionQuality
	] = compressionQuality

	updateExifDimensions(
		in: &outputProperties,
		width: resizedImage.width,
		height: resizedImage.height
	)

	CGImageDestinationAddImage(
		destination,
		resizedImage,
		outputProperties as CFDictionary
	)

	var auxiliaryResults:
		[AuxiliaryMapKind: AuxiliaryMapResult] = [:]

	for option in auxiliaryOptions {
		auxiliaryResults[option.kind] =
			try processAuxiliaryImage(
				option,
				from: source,
				imageIndex: imageIndex,
				to: destination,
				previewDirectory: previewDirectory
			)
	}

	guard CGImageDestinationFinalize(destination) else {
		throw HEICResizeError.couldNotFinalizeDestination
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


// MARK: - Auxiliary images

private struct ResolvedAuxiliaryImage {
	let type: CFString

	let info: CFDictionary
}


//combined depth/disparity
private func resolveAuxiliaryImage(
	for kind: AuxiliaryMapKind,
	from source: CGImageSource,
	imageIndex: Int
) -> ResolvedAuxiliaryImage? {

	for type in kind.possibleImageIOTypes {
		if let info =
			CGImageSourceCopyAuxiliaryDataInfoAtIndex(
				source,
				imageIndex,
				type
			) {

			return ResolvedAuxiliaryImage(
				type: type,
				info: info
			)
		}
	}

	return nil
}


private func processAuxiliaryImage(
	_ option: AuxiliaryMapOption,
	from source: CGImageSource,
	imageIndex: Int,
	to destination: CGImageDestination,
	previewDirectory: URL
) throws -> AuxiliaryMapResult {

	guard let resolvedAuxiliary =
		resolveAuxiliaryImage(
			for: option.kind,
			from: source,
			imageIndex: imageIndex
		)
	else {
		return .absent
	}
	//combined depth/disparity
	let type = resolvedAuxiliary.type
	let auxiliaryInfo = resolvedAuxiliary.info

	let originalDimensions =
		auxiliaryDimensions(from: auxiliaryInfo)
		?? PixelDimensions(
			width: 0,
			height: 0
		)

	guard option.enabled else {
		print(
			"Discarded \(option.kind.displayName)"
		)

		return .discarded(
			original: originalDimensions
		)
	}

	do {
		let resized = try resizeAuxiliaryData(
			auxiliaryInfo,
			scale: option.scale
		)

		CGImageDestinationAddAuxiliaryDataInfo(
			destination,
			type,
			resized.auxiliaryInfo
		)

		let previewURL = makeAuxiliaryPreviewURL(
			for: option.kind,
			in: previewDirectory
		)

		let preview = createAuxiliaryPreview(
			from: resized.auxiliaryInfo,
			at: previewURL
		)

		print(
			"""
			Resized \(option.kind.displayName): \
			\(resized.originalDimensions.description) → \
			\(resized.outputDimensions.description)
			"""
		)

		return .resized(
			original: resized.originalDimensions,
			output: resized.outputDimensions,
			preview: preview
		)

	} catch AuxiliaryResizeError
		.unsupportedPixelFormat(let pixelFormat) {

		// Preserve an unknown maps
		CGImageDestinationAddAuxiliaryDataInfo(
			destination,
			type,
			auxiliaryInfo
		)

		let previewURL = makeAuxiliaryPreviewURL(
			for: option.kind,
			in: previewDirectory
		)

		let preview = createAuxiliaryPreview(
			from: auxiliaryInfo,
			at: previewURL
		)

		let reason =
			"Unsupported pixel format \(pixelFormat)"

		print(
			"""
			Warning: \(option.kind.displayName) was retained \
			unchanged. \(reason).
			"""
		)

		return .retainedUnchanged(
			original: originalDimensions,
			reason: reason,
			preview: preview
		)

	} catch {
		throw error
	}
}


// MARK: - Preview generation

private func makeAuxiliaryPreviewURL(
	for kind: AuxiliaryMapKind,
	in directory: URL
) -> URL {

	directory.appendingPathComponent(
		"\(kind.rawValue).png"
	)
}


private func createAuxiliaryPreview(
	from auxiliaryInfo: CFDictionary,
	at outputURL: URL
) -> ImagePreview {

	do {
		try writeAuxiliaryPreviewPNG(
			auxiliaryInfo,
			to: outputURL
		)

		return ImagePreview(
			url: outputURL
		)

	} catch {
		// prevent failure due to preview generation issues
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


// MARK: - Metadata

private func updateExifDimensions(
	in properties: inout [CFString: Any],
	width: Int,
	height: Int
) {

	guard var exif =
		properties[
			kCGImagePropertyExifDictionary
		] as? [CFString: Any]
	else {
		return
	}

	exif[kCGImagePropertyExifPixelXDimension] =
		width

	exif[kCGImagePropertyExifPixelYDimension] =
		height

	properties[kCGImagePropertyExifDictionary] =
		exif
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
