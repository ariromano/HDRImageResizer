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
	case couldNotOpenSource
	case couldNotCreateDestination
	case missingImageDimensions
	case couldNotCreateThumbnail
	case couldNotFinalizeDestination

	var errorDescription: String? {
		switch self {
		case .invalidScale(let scale):
			return "Invalid image scale: \(scale)."

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
	auxiliaryOptions: [AuxiliaryMapOption]
) throws -> HEICResizeResult {

	guard scale > 0, scale <= 1 else {
		throw HEICResizeError.invalidScale(scale)
	}

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
		let width =
			numberAsInt(
				properties[kCGImagePropertyPixelWidth]
			),
		let height =
			numberAsInt(
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
			true
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

	outputProperties[kCGImagePropertyOrientation] = 1

	if var exif = outputProperties[
		kCGImagePropertyExifDictionary
	] as? [CFString: Any] {

		exif[kCGImagePropertyExifPixelXDimension] =
			resizedImage.width

		exif[kCGImagePropertyExifPixelYDimension] =
			resizedImage.height

		outputProperties[kCGImagePropertyExifDictionary] =
			exif
	}

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
				to: destination
			)
	}

	guard CGImageDestinationFinalize(destination) else {
		throw HEICResizeError.couldNotFinalizeDestination
	}

	return HEICResizeResult(
		fileName: inputURL.lastPathComponent,
		mainImageOriginal: originalDimensions,
		mainImageOutput: outputDimensions,
		auxiliaryResults: auxiliaryResults
	)
}


// MARK: - Auxiliary images

private func processAuxiliaryImage(
	_ option: AuxiliaryMapOption,
	from source: CGImageSource,
	imageIndex: Int,
	to destination: CGImageDestination
) throws -> AuxiliaryMapResult {

	let type = option.kind.imageIOType

	guard let auxiliaryInfo =
		CGImageSourceCopyAuxiliaryDataInfoAtIndex(
			source,
			imageIndex,
			type
		)
	else {
		return .absent
	}

	let originalDimensions =
		auxiliaryDimensions(from: auxiliaryInfo)
		?? PixelDimensions(width: 0, height: 0)

	guard option.isEnabled else {
		print("Discarded \(option.kind.displayName)")

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

		print(
			"""
			Resized \(option.kind.displayName): \
			\(resized.originalDimensions.description) → \
			\(resized.outputDimensions.description)
			"""
		)

		return .resized(
			original: resized.originalDimensions,
			output: resized.outputDimensions
		)

	} catch AuxiliaryResizeError
		.unsupportedPixelFormat(let pixelFormat) {

		CGImageDestinationAddAuxiliaryDataInfo(
			destination,
			type,
			auxiliaryInfo
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
			reason: reason
		)

	} catch {
		throw error
	}
}


// MARK: - Helpers

private func numberAsInt(
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
