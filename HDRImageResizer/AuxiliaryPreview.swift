//
//  AuxiliaryPreview.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 8/1/26.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers


enum AuxiliaryPreviewError: LocalizedError {
	case invalidDictionary
	case missingData
	case missingDescription
	case missingValue(String)
	case invalidDimensions
	case invalidBytesPerRow
	case unsupportedPixelFormat(UInt32)
	case insufficientData(expected: Int, actual: Int)
	case couldNotCreateImage
	case couldNotCreateDestination
	case couldNotWritePNG

	var errorDescription: String? {
		switch self {
		case .invalidDictionary:
			return "The auxiliary-image dictionary is invalid."

		case .missingData:
			return "The auxiliary image contains no pixel data."

		case .missingDescription:
			return "The auxiliary image has no data description."

		case .missingValue(let key):
			return "The auxiliary-image description is missing “\(key)”."

		case .invalidDimensions:
			return "The auxiliary image has invalid dimensions."

		case .invalidBytesPerRow:
			return "The auxiliary image has an invalid row stride."

		case .unsupportedPixelFormat(let format):
			return """
			Cannot preview unsupported auxiliary pixel format \
			\(previewFourCharacterString(format)) (\(format)).
			"""

		case .insufficientData(let expected, let actual):
			return """
			The auxiliary pixel buffer is too small. \
			Expected at least \(expected) bytes, but found \(actual).
			"""

		case .couldNotCreateImage:
			return "Could not create the auxiliary preview image."

		case .couldNotCreateDestination:
			return "Could not create the PNG destination."

		case .couldNotWritePNG:
			return "Could not write the auxiliary preview PNG."
		}
	}
}


/// Writes a visible grayscale PNG representation of an ImageIO auxiliary image.
///
/// Supported formats:
/// - `L008`: 8-bit unsigned grayscale
/// - `L016`: 16-bit unsigned grayscale
/// - `Lf32`: 32-bit floating-point grayscale
///
/// `L016` and `Lf32` are normalized to the full 0–255 range for viewing.
/// The preview does not alter the auxiliary data stored in the HEIC.
func writeAuxiliaryPreviewPNG(
	_ auxiliaryInfo: CFDictionary,
	to outputURL: URL
) throws {

	let image = try makeAuxiliaryPreviewImage(
		from: auxiliaryInfo
	)

	guard let destination =
		CGImageDestinationCreateWithURL(
			outputURL as CFURL,
			UTType.png.identifier as CFString,
			1,
			nil
		)
	else {
		throw AuxiliaryPreviewError
			.couldNotCreateDestination
	}

	CGImageDestinationAddImage(
		destination,
		image,
		nil
	)

	guard CGImageDestinationFinalize(destination) else {
		throw AuxiliaryPreviewError.couldNotWritePNG
	}
}


// MARK: - Image creation

private func makeAuxiliaryPreviewImage(
	from auxiliaryInfo: CFDictionary
) throws -> CGImage {

	guard
		let info =
			auxiliaryInfo as? [CFString: Any]
	else {
		throw AuxiliaryPreviewError.invalidDictionary
	}

	guard
		let data =
			info[kCGImageAuxiliaryDataInfoData] as? Data
	else {
		throw AuxiliaryPreviewError.missingData
	}

	guard
		let description =
			info[
				kCGImageAuxiliaryDataInfoDataDescription
			] as? [CFString: Any]
	else {
		throw AuxiliaryPreviewError.missingDescription
	}

	let width = try previewInteger(
		description[previewWidthKey],
		key: previewWidthKey as String
	)

	let height = try previewInteger(
		description[previewHeightKey],
		key: previewHeightKey as String
	)

	let bytesPerRow = try previewInteger(
		description[previewBytesPerRowKey],
		key: previewBytesPerRowKey as String
	)

	let pixelFormat = try previewUInt32(
		description[previewPixelFormatKey],
		key: previewPixelFormatKey as String
	)

	guard width > 0, height > 0 else {
		throw AuxiliaryPreviewError.invalidDimensions
	}

	guard bytesPerRow > 0 else {
		throw AuxiliaryPreviewError.invalidBytesPerRow
	}

	let requiredByteCount = bytesPerRow * height

	guard data.count >= requiredByteCount else {
		throw AuxiliaryPreviewError.insufficientData(
			expected: requiredByteCount,
			actual: data.count
		)
	}

	let grayscaleData: Data

	switch pixelFormat {
	case previewFourCharacterCode("L008"):
		grayscaleData = extractPlanar8(
			data: data,
			width: width,
			height: height,
			bytesPerRow: bytesPerRow
		)

	case previewFourCharacterCode("L016"):
		guard bytesPerRow.isMultiple(of: 2) else {
			throw AuxiliaryPreviewError.invalidBytesPerRow
		}

		grayscaleData = normalizePlanar16(
			data: data,
			width: width,
			height: height,
			bytesPerRow: bytesPerRow
		)

	case previewFourCharacterCode("Lf32"):
		guard bytesPerRow.isMultiple(of: 4) else {
			throw AuxiliaryPreviewError.invalidBytesPerRow
		}

		grayscaleData = normalizePlanarFloat(
			data: data,
			width: width,
			height: height,
			bytesPerRow: bytesPerRow
		)

	default:
		throw AuxiliaryPreviewError
			.unsupportedPixelFormat(pixelFormat)
	}

	guard
		let provider = CGDataProvider(
			data: grayscaleData as CFData
		),
		let image = CGImage(
			width: width,
			height: height,
			bitsPerComponent: 8,
			bitsPerPixel: 8,
			bytesPerRow: width,
			space: CGColorSpaceCreateDeviceGray(),
			bitmapInfo: CGBitmapInfo(
				rawValue:
					CGImageAlphaInfo.none.rawValue
			),
			provider: provider,
			decode: nil,
			shouldInterpolate: false,
			intent: .defaultIntent
		)
	else {
		throw AuxiliaryPreviewError.couldNotCreateImage
	}

	return image
}


// MARK: - L008

private func extractPlanar8(
	data: Data,
	width: Int,
	height: Int,
	bytesPerRow: Int
) -> Data {

	var output = Data(
		count: width * height
	)

	data.withUnsafeBytes { sourceBytes in
		output.withUnsafeMutableBytes {
			destinationBytes in

			guard
				let source =
					sourceBytes.baseAddress,
				let destination =
					destinationBytes.baseAddress
			else {
				return
			}

			for row in 0..<height {
				memcpy(
					destination.advanced(
						by: row * width
					),
					source.advanced(
						by: row * bytesPerRow
					),
					width
				)
			}
		}
	}

	return output
}


// MARK: - L016

private func normalizePlanar16(
	data: Data,
	width: Int,
	height: Int,
	bytesPerRow: Int
) -> Data {

	let pixelCount = width * height

	var values = [UInt16]()
	values.reserveCapacity(pixelCount)

	data.withUnsafeBytes { bytes in
		guard let baseAddress = bytes.baseAddress else {
			return
		}

		for row in 0..<height {
			let rowPointer = baseAddress
				.advanced(by: row * bytesPerRow)
				.assumingMemoryBound(to: UInt16.self)

			for column in 0..<width {
				values.append(rowPointer[column])
			}
		}
	}

	guard
		values.count == pixelCount,
		let minimum = values.min(),
		let maximum = values.max()
	else {
		return Data(
			repeating: 0,
			count: pixelCount
		)
	}

	guard maximum > minimum else {
		return Data(
			repeating: 0,
			count: pixelCount
		)
	}

	let range =
		Double(maximum) - Double(minimum)

	let output = values.map { value -> UInt8 in
		let normalized =
			(Double(value) - Double(minimum))
			/ range

		return UInt8(
			clamping:
				Int((normalized * 255).rounded())
		)
	}

	return Data(output)
}


// MARK: - Lf32

private func normalizePlanarFloat(
	data: Data,
	width: Int,
	height: Int,
	bytesPerRow: Int
) -> Data {

	let pixelCount = width * height

	var values = [Float]()
	values.reserveCapacity(pixelCount)

	data.withUnsafeBytes { bytes in
		guard let baseAddress = bytes.baseAddress else {
			return
		}

		for row in 0..<height {
			let rowPointer = baseAddress
				.advanced(by: row * bytesPerRow)
				.assumingMemoryBound(to: Float.self)

			for column in 0..<width {
				let value = rowPointer[column]

				values.append(
					value.isFinite ? value : 0
				)
			}
		}
	}

	guard
		values.count == pixelCount,
		let minimum = values.min(),
		let maximum = values.max()
	else {
		return Data(
			repeating: 0,
			count: pixelCount
		)
	}

	guard maximum > minimum else {
		return Data(
			repeating: 0,
			count: pixelCount
		)
	}

	let range = maximum - minimum

	let output = values.map { value -> UInt8 in
		let normalized =
			(value - minimum) / range

		return UInt8(
			clamping:
				Int((normalized * 255).rounded())
		)
	}

	return Data(output)
}


// MARK: - Description parsing

private let previewWidthKey =
	"Width" as CFString

private let previewHeightKey =
	"Height" as CFString

private let previewBytesPerRowKey =
	"BytesPerRow" as CFString

private let previewPixelFormatKey =
	"PixelFormat" as CFString


private func previewInteger(
	_ value: Any?,
	key: String
) throws -> Int {

	if let value = value as? Int {
		return value
	}

	if let value = value as? NSNumber {
		return value.intValue
	}

	throw AuxiliaryPreviewError.missingValue(key)
}


private func previewUInt32(
	_ value: Any?,
	key: String
) throws -> UInt32 {

	if let value = value as? UInt32 {
		return value
	}

	if let value = value as? Int {
		return UInt32(
			truncatingIfNeeded: value
		)
	}

	if let value = value as? NSNumber {
		return value.uint32Value
	}

	throw AuxiliaryPreviewError.missingValue(key)
}


// MARK: - Four-character codes

private func previewFourCharacterCode(
	_ string: String
) -> UInt32 {

	precondition(
		string.utf8.count == 4,
		"A FourCC must contain exactly four UTF-8 bytes."
	)

	return string.utf8.reduce(UInt32(0)) {
		($0 << 8) | UInt32($1)
	}
}


private func previewFourCharacterString(
	_ value: UInt32
) -> String {

	let bytes: [UInt8] = [
		UInt8((value >> 24) & 0xff),
		UInt8((value >> 16) & 0xff),
		UInt8((value >> 8) & 0xff),
		UInt8(value & 0xff)
	]

	let printableBytes = bytes.map { byte in
		(32...126).contains(byte)
			? byte
			: UInt8(ascii: "?")
	}

	return String(
		bytes: printableBytes,
		encoding: .ascii
	) ?? "????"
}
