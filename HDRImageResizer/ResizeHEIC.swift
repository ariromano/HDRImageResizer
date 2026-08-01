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
) throws {

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
		let width = properties[kCGImagePropertyPixelWidth] as? Int,
		let height = properties[kCGImagePropertyPixelHeight] as? Int
	else {
		throw HEICResizeError.missingImageDimensions
	}

	let maximumPixelSize = max(
		1,
		Int(
			(CGFloat(max(width, height)) * scale)
				.rounded()
		)
	)

	let thumbnailOptions: [CFString: Any] = [
		kCGImageSourceCreateThumbnailFromImageAlways: true,
		kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
		kCGImageSourceCreateThumbnailWithTransform: true
	]

	guard let resizedImage = CGImageSourceCreateThumbnailAtIndex(
		source,
		imageIndex,
		thumbnailOptions as CFDictionary
	) else {
		throw HEICResizeError.couldNotCreateThumbnail
	}

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

	for option in auxiliaryOptions {
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
}


// MARK: - Auxiliary images

private func processAuxiliaryImage(
	_ option: AuxiliaryMapOption,
	from source: CGImageSource,
	imageIndex: Int,
	to destination: CGImageDestination
) throws {

	let type = option.kind.imageIOType

	guard let auxiliaryInfo =
		CGImageSourceCopyAuxiliaryDataInfoAtIndex(
			source,
			imageIndex,
			type
		)
	else {
		// The source simply does not contain this map type.
		return
	}

	guard option.isEnabled else {
		print("Discarded \(option.kind.displayName)")
		return
	}

	do {
		let resizedAuxiliaryInfo =
			try resizeAuxiliaryData(
				auxiliaryInfo,
				scale: option.scale
			)

		CGImageDestinationAddAuxiliaryDataInfo(
			destination,
			type,
			resizedAuxiliaryInfo
		)

		print(
			"Resized \(option.kind.displayName) to "
			+ "\(Int(option.scale * 100))%"
		)

	} catch AuxiliaryResizeError.unsupportedPixelFormat(
		let pixelFormat
	) {
		//Preserve unknown formats unchanged over dropping the auxiliary image and potentially destroying HDR or other data.

		CGImageDestinationAddAuxiliaryDataInfo(
			destination,
			type,
			auxiliaryInfo
		)

		print(
			"""
			Warning: \(option.kind.displayName) uses unsupported pixel \
			format \(pixelFormat). It was retained at its original size.
			"""
		)

	} catch {
		throw error
	}
}
