//
//  ResizeHEIC.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import ImageIO
import UniformTypeIdentifiers


func resizeHEIC(from inputURL: URL, to outputURL: URL) throws {

	guard let source = CGImageSourceCreateWithURL(
		inputURL as CFURL,
		nil
	) else {
		throw NSError(domain: "HDRResize", code: 1)
	}


	guard let destination = CGImageDestinationCreateWithURL(
		outputURL as CFURL,
		UTType.heic.identifier as CFString,
		1,
		nil
	) else {
		throw NSError(domain: "HDRResize", code: 2)
	}


	let imageIndex = 0


	// create a 50% scale version
	guard let properties =
			CGImageSourceCopyPropertiesAtIndex(
				source,
				imageIndex,
				nil
			) as? [CFString: Any],
		  let width =
			properties[kCGImagePropertyPixelWidth] as? Int,
		  let height =
			properties[kCGImagePropertyPixelHeight] as? Int
	else {
		throw NSError(domain: "HDRResize", code: 3)
	}


	let options: [CFString: Any] = [
		kCGImageSourceCreateThumbnailFromImageAlways: true,
		kCGImageSourceThumbnailMaxPixelSize:
			max(width, height) / 2,
		kCGImageSourceCreateThumbnailWithTransform: true
	]


	guard let thumbnail =
			CGImageSourceCreateThumbnailAtIndex(
				source,
				imageIndex,
				options as CFDictionary
			)
	else {
		throw NSError(domain: "HDRResize", code: 4)
	}


	// Preserve metadata
	let metadata =
		CGImageSourceCopyPropertiesAtIndex(
			source,
			imageIndex,
			nil
		)


	CGImageDestinationAddImage(
		destination,
		thumbnail,
		metadata ?? [:] as CFDictionary
	)


	// preserve HDR gain map
	let auxTypes: [CFString] = [
		kCGImageAuxiliaryDataTypeHDRGainMap
	]

	for type in auxTypes {

		if let auxInfo =
			CGImageSourceCopyAuxiliaryDataInfoAtIndex(
				source,
				imageIndex,
				type
			) {

			CGImageDestinationAddAuxiliaryDataInfo(
				destination,
				type,
				auxInfo
			)

			print("Copied auxiliary data:", type)
		}
	}


	guard CGImageDestinationFinalize(destination)
	else {
		throw NSError(domain: "HDRResize", code: 5)
	}
}
