//
//  ResizeAuxiliary.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 8/1/26.
//

//
//  ResizeAuxiliary.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 8/1/26.
//

import Foundation
import Accelerate
import ImageIO
import CoreGraphics


struct ResizedAuxiliaryData {
	let auxiliaryInfo: CFDictionary
	let originalDimensions: PixelDimensions
	let outputDimensions: PixelDimensions
}


enum AuxiliaryResizeError: LocalizedError {
	case invalidScale(CGFloat)
	case invalidDictionary
	case missingData
	case missingDescription
	case missingDescriptionValue(String)
	case invalidDimensions(width: Int, height: Int)
	case invalidBytesPerRow(Int)
	case insufficientData(expected: Int, actual: Int)
	case unsupportedPixelFormat(UInt32)
	case invalidDataAlignment(format: String)
	case resizeFailed(vImage_Error)

	var errorDescription: String? {
		switch self {
		case .invalidScale(let scale):
			return "Invalid auxiliary-image scale: \(scale)"

		case .invalidDictionary:
			return "The auxiliary-image dictionary is invalid."

		case .missingData:
			return "The auxiliary image contains no pixel data."

		case .missingDescription:
			return "The auxiliary image contains no data description."

		case .missingDescriptionValue(let key):
			return "The auxiliary-image description is missing “\(key)”."

		case .invalidDimensions(let width, let height):
			return "Invalid auxiliary-image dimensions: \(width) × \(height)."

		case .invalidBytesPerRow(let bytesPerRow):
			return "Invalid auxiliary-image row stride: \(bytesPerRow) bytes."

		case .insufficientData(let expected, let actual):
			return """
			The auxiliary-image buffer is too small. \
			Expected at least \(expected) bytes, but found \(actual).
			"""

		case .unsupportedPixelFormat(let format):
			return """
			Unsupported auxiliary-image pixel format: \
			\(fourCharacterString(format)) (\(format)).
			"""

		case .invalidDataAlignment(let format):
			return """
			The auxiliary-image data is not correctly aligned \
			for \(format).
			"""

		case .resizeFailed(let error):
			return """
			vImage failed to resize the auxiliary image. \
			Error: \(error).
			"""
		}
	}
}


/// Resizes an ImageIO auxiliary image while preserving its metadata.
///
/// Supported formats:
/// - `L008`: 8-bit unsigned grayscale
/// - `L016`: 16-bit unsigned grayscale
/// - `Lf32`: 32-bit floating-point grayscale
///
/// Unknown formats print a warning and throw
/// `AuxiliaryResizeError.unsupportedPixelFormat`.
func resizeAuxiliaryData(
	_ auxiliaryInfo: CFDictionary,
	scale: CGFloat
) throws -> ResizedAuxiliaryData {

	guard scale > 0 else {
		throw AuxiliaryResizeError.invalidScale(scale)
	}

	guard var info = auxiliaryInfo as? [CFString: Any] else {
		throw AuxiliaryResizeError.invalidDictionary
	}

	guard
		let sourceData =
			info[kCGImageAuxiliaryDataInfoData] as? Data
	else {
		throw AuxiliaryResizeError.missingData
	}

	guard
		var description =
			info[kCGImageAuxiliaryDataInfoDataDescription]
				as? [CFString: Any]
	else {
		throw AuxiliaryResizeError.missingDescription
	}

	let width = try integerValue(
		in: description,
		key: auxiliaryWidthKey
	)

	let height = try integerValue(
		in: description,
		key: auxiliaryHeightKey
	)

	let sourceBytesPerRow = try integerValue(
		in: description,
		key: auxiliaryBytesPerRowKey
	)

	let pixelFormat = try pixelFormatValue(
		in: description,
		key: auxiliaryPixelFormatKey
	)

	guard width > 0, height > 0 else {
		throw AuxiliaryResizeError.invalidDimensions(
			width: width,
			height: height
		)
	}

	guard sourceBytesPerRow > 0 else {
		throw AuxiliaryResizeError.invalidBytesPerRow(
			sourceBytesPerRow
		)
	}

	let requiredSourceBytes =
		sourceBytesPerRow * height

	guard sourceData.count >= requiredSourceBytes else {
		throw AuxiliaryResizeError.insufficientData(
			expected: requiredSourceBytes,
			actual: sourceData.count
		)
	}

	let destinationWidth = max(
		1,
		Int(
			(CGFloat(width) * scale)
				.rounded()
		)
	)

	let destinationHeight = max(
		1,
		Int(
			(CGFloat(height) * scale)
				.rounded()
		)
	)

	guard let format = AuxiliaryPixelFormat(pixelFormat) else {
		print(
			"""
			Warning: auxiliary image was not resized because its \
			pixel format is unsupported: \
			\(fourCharacterString(pixelFormat)) (\(pixelFormat))
			"""
		)

		throw AuxiliaryResizeError.unsupportedPixelFormat(
			pixelFormat
		)
	}

	guard
		sourceBytesPerRow.isMultiple(
			of: format.byteAlignment
		)
	else {
		throw AuxiliaryResizeError.invalidDataAlignment(
			format: format.name
		)
	}

	let destinationBytesPerRow =
		destinationWidth * format.bytesPerPixel

	let resizedData = try resizeBuffer(
		sourceData: sourceData,
		sourceWidth: width,
		sourceHeight: height,
		sourceBytesPerRow: sourceBytesPerRow,
		destinationWidth: destinationWidth,
		destinationHeight: destinationHeight,
		destinationBytesPerRow:
			destinationBytesPerRow,
		alignment: format.byteAlignment,
		scaleOperation: format.scaleOperation
	)

	description[auxiliaryWidthKey] =
		destinationWidth

	description[auxiliaryHeightKey] =
		destinationHeight

	description[auxiliaryBytesPerRowKey] =
		destinationBytesPerRow

	info[kCGImageAuxiliaryDataInfoData] =
		resizedData

	info[kCGImageAuxiliaryDataInfoDataDescription] =
		description

	return ResizedAuxiliaryData(
		auxiliaryInfo: info as CFDictionary,
		originalDimensions: PixelDimensions(
			width: width,
			height: height
		),
		outputDimensions: PixelDimensions(
			width: destinationWidth,
			height: destinationHeight
		)
	)
}


/// Returns the dimensions stored in an ImageIO auxiliary-data dictionary.
///
/// Returns `nil` when the dictionary does not contain readable width and
/// height values.
func auxiliaryDimensions(
	from auxiliaryInfo: CFDictionary
) -> PixelDimensions? {

	guard
		let info =
			auxiliaryInfo as? [CFString: Any],
		let description =
			info[
				kCGImageAuxiliaryDataInfoDataDescription
			] as? [CFString: Any],
		let width = optionalIntegerValue(
			description[auxiliaryWidthKey]
		),
		let height = optionalIntegerValue(
			description[auxiliaryHeightKey]
		)
	else {
		return nil
	}

	return PixelDimensions(
		width: width,
		height: height
	)
}


// MARK: - Pixel formats

private struct AuxiliaryPixelFormat {

	typealias ScaleOperation = (
		inout vImage_Buffer,
		inout vImage_Buffer
	) -> vImage_Error

	let name: String
	let bytesPerPixel: Int
	let byteAlignment: Int
	let scaleOperation: ScaleOperation


	private init(
		name: String,
		bytesPerPixel: Int,
		byteAlignment: Int,
		scaleOperation: @escaping ScaleOperation
	) {
		self.name = name
		self.bytesPerPixel = bytesPerPixel
		self.byteAlignment = byteAlignment
		self.scaleOperation = scaleOperation
	}


	init?(_ fourCC: UInt32) {
		switch fourCC {
		case fourCharacterCode("L008"):
			self = Self.planar(
				name: "L008",
				component: UInt8.self
			) { source, destination in
				vImageScale_Planar8(
					&source,
					&destination,
					nil,
					vImage_Flags(
						kvImageHighQualityResampling
					)
				)
			}

		case fourCharacterCode("L016"):
			self = Self.planar(
				name: "L016",
				component: UInt16.self
			) { source, destination in
				vImageScale_Planar16U(
					&source,
					&destination,
					nil,
					vImage_Flags(
						kvImageHighQualityResampling
					)
				)
			}

		case fourCharacterCode("Lf32"):
			self = Self.planar(
				name: "Lf32",
				component: Float.self
			) { source, destination in
				vImageScale_PlanarF(
					&source,
					&destination,
					nil,
					vImage_Flags(
						kvImageHighQualityResampling
					)
				)
			}

		default:
			return nil
		}
	}


	private static func planar<Component>(
		name: String,
		component: Component.Type,
		scaleOperation: @escaping ScaleOperation
	) -> Self {

		Self(
			name: name,
			bytesPerPixel:
				MemoryLayout<Component>.size,
			byteAlignment:
				MemoryLayout<Component>.alignment,
			scaleOperation: scaleOperation
		)
	}
}


// MARK: - Buffer scaling

private func resizeBuffer(
	sourceData: Data,
	sourceWidth: Int,
	sourceHeight: Int,
	sourceBytesPerRow: Int,
	destinationWidth: Int,
	destinationHeight: Int,
	destinationBytesPerRow: Int,
	alignment: Int,
	scaleOperation:
		AuxiliaryPixelFormat.ScaleOperation
) throws -> Data {

	let sourceByteCount =
		sourceBytesPerRow * sourceHeight

	let destinationByteCount =
		destinationBytesPerRow
		* destinationHeight

	let sourcePointer =
		UnsafeMutableRawPointer.allocate(
			byteCount: sourceByteCount,
			alignment: alignment
		)

	let destinationPointer =
		UnsafeMutableRawPointer.allocate(
			byteCount: destinationByteCount,
			alignment: alignment
		)

	defer {
		sourcePointer.deallocate()
		destinationPointer.deallocate()
	}

	sourceData.copyBytes(
		to: sourcePointer
			.assumingMemoryBound(to: UInt8.self),
		count: sourceByteCount
	)

	destinationPointer.initializeMemory(
		as: UInt8.self,
		repeating: 0,
		count: destinationByteCount
	)

	var sourceBuffer = vImage_Buffer(
		data: sourcePointer,
		height: vImagePixelCount(sourceHeight),
		width: vImagePixelCount(sourceWidth),
		rowBytes: sourceBytesPerRow
	)

	var destinationBuffer = vImage_Buffer(
		data: destinationPointer,
		height: vImagePixelCount(destinationHeight),
		width: vImagePixelCount(destinationWidth),
		rowBytes: destinationBytesPerRow
	)

	let result = scaleOperation(
		&sourceBuffer,
		&destinationBuffer
	)

	guard result == kvImageNoError else {
		throw AuxiliaryResizeError.resizeFailed(
			result
		)
	}

	return Data(
		bytes: destinationPointer,
		count: destinationByteCount
	)
}


// MARK: - Description parsing

private let auxiliaryWidthKey =
	"Width" as CFString

private let auxiliaryHeightKey =
	"Height" as CFString

private let auxiliaryBytesPerRowKey =
	"BytesPerRow" as CFString

private let auxiliaryPixelFormatKey =
	"PixelFormat" as CFString


private func integerValue(
	in dictionary: [CFString: Any],
	key: CFString
) throws -> Int {

	if let value = optionalIntegerValue(
		dictionary[key]
	) {
		return value
	}

	throw AuxiliaryResizeError
		.missingDescriptionValue(
			key as String
		)
}


private func optionalIntegerValue(
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


private func pixelFormatValue(
	in dictionary: [CFString: Any],
	key: CFString
) throws -> UInt32 {

	if let value = dictionary[key] as? UInt32 {
		return value
	}

	if let value = dictionary[key] as? Int {
		return UInt32(
			truncatingIfNeeded: value
		)
	}

	if let value = dictionary[key] as? NSNumber {
		return value.uint32Value
	}

	throw AuxiliaryResizeError
		.missingDescriptionValue(
			key as String
		)
}


// MARK: - Four-character codes

private func fourCharacterCode(
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


private func fourCharacterString(
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
