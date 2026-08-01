//
//  testCoreImageHDR.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 8/1/26.
//


import Foundation
import CoreImage
import CoreGraphics
import ImageIO


enum TestConversionError: LocalizedError {
	case invalidArguments
	case couldNotLoadImage
	case couldNotCreatePQColorSpace

	var errorDescription: String? {
		switch self {
		case .invalidArguments:
			return """
			Usage:
				swift testCoreImageHDR.swift input.heic output.heic
			"""

		case .couldNotLoadImage:
			return "Core Image could not load the input image."

		case .couldNotCreatePQColorSpace:
			return "Could not create the BT.2100 PQ color space."
		}
	}
}


func convertHDRHEIC(
	from inputURL: URL,
	to outputURL: URL
) throws {

	let scale: CGFloat = 1.0
	let compressionQuality = 1.0

	let loadOptions: [CIImageOption: Any] = [
		.applyOrientationProperty: true,
		.expandToHDR: true
	]

	guard let sourceImage = CIImage(
		contentsOf: inputURL,
		options: loadOptions
	) else {
		throw TestConversionError.couldNotLoadImage
	}

	print("Input extent:", sourceImage.extent)
	print(
		"Input color space:",
		String(describing: sourceImage.colorSpace)
	)

	let scaledImage = sourceImage.applyingFilter(
		"CILanczosScaleTransform",
		parameters: [
			kCIInputScaleKey: scale,
			kCIInputAspectRatioKey: 1.0
		]
	)

	let translatedImage = scaledImage.transformed(
		by: CGAffineTransform(
			translationX: -scaledImage.extent.origin.x,
			y: -scaledImage.extent.origin.y
		)
	)

	let outputWidth = max(
		1,
		Int(
			(sourceImage.extent.width * scale)
				.rounded()
		)
	)

	let outputHeight = max(
		1,
		Int(
			(sourceImage.extent.height * scale)
				.rounded()
		)
	)

	let outputImage = translatedImage.cropped(
		to: CGRect(
			x: 0,
			y: 0,
			width: outputWidth,
			height: outputHeight
		)
	)

	guard let pqColorSpace = CGColorSpace(
		name: CGColorSpace.itur_2100_PQ
	) else {
		throw TestConversionError
			.couldNotCreatePQColorSpace
	}

	let context = CIContext(
		options: [
			.workingColorSpace: pqColorSpace,
			.outputColorSpace: pqColorSpace
		]
	)

	if FileManager.default.fileExists(
		atPath: outputURL.path
	) {
		try FileManager.default.removeItem(
			at: outputURL
		)
	}

	let qualityOption = CIImageRepresentationOption(
		rawValue:
			kCGImageDestinationLossyCompressionQuality
				as String
	)

	try context.writeHEIF10Representation(
		of: outputImage,
		to: outputURL,
		colorSpace: pqColorSpace,
		options: [
			qualityOption: compressionQuality
		]
	)

	print("Output extent:", outputImage.extent)
	print("Output color space:", pqColorSpace)
	print("Written to:", outputURL.path)
}


do {
	guard CommandLine.arguments.count == 3 else {
		throw TestConversionError.invalidArguments
	}

	let inputURL = URL(
		fileURLWithPath: CommandLine.arguments[1]
	)

	let outputURL = URL(
		fileURLWithPath: CommandLine.arguments[2]
	)

	try convertHDRHEIC(
		from: inputURL,
		to: outputURL
	)

} catch {
	fputs(
		"Error: \(error.localizedDescription)\n",
		stderr
	)

	exit(1)
}
