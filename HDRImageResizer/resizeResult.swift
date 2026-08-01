//
//  ResizeResult.swift
//  HDRImageResizer
//

import Foundation


struct PixelDimensions: Equatable {
	let width: Int
	let height: Int

	var description: String {
		"\(width) × \(height)"
	}
}


struct ImagePreview {
	let url: URL?
}


enum AuxiliaryMapResult {
	case absent

	case discarded(
		original: PixelDimensions
	)

	case resized(
		original: PixelDimensions,
		output: PixelDimensions,
		preview: ImagePreview
	)

	case retainedUnchanged(
		original: PixelDimensions,
		reason: String,
		preview: ImagePreview
	)


	var summary: String {
		switch self {
		case .absent:
			return "Not present"

		case .discarded(let original):
			return "\(original.description) → discarded"

		case .resized(
			let original,
			let output,
			_
		):
			return """
			\(original.description) → \
			\(output.description)
			"""

		case .retainedUnchanged(
			let original,
			_,
			_
		):
			return "\(original.description) → unchanged"
		}
	}


	var preview: ImagePreview? {
		switch self {
		case .absent:
			return nil

		case .discarded:
			return nil

		case .resized(
			_,
			_,
			let preview
		):
			return preview

		case .retainedUnchanged(
			_,
			_,
			let preview
		):
			return preview
		}
	}
}


struct HEICResizeResult {
	let fileName: String

	let mainImageOriginal: PixelDimensions
	let mainImageOutput: PixelDimensions

	let mainImagePreview: ImagePreview

	let auxiliaryResults:
		[AuxiliaryMapKind: AuxiliaryMapResult]


	var mainImageSummary: String {
		"""
		\(mainImageOriginal.description) → \
		\(mainImageOutput.description)
		"""
	}


	func result(
		for kind: AuxiliaryMapKind
	) -> AuxiliaryMapResult? {
		auxiliaryResults[kind]
	}


	func replacingMainImagePreview(
		with url: URL
	) -> HEICResizeResult {

		HEICResizeResult(
			fileName: fileName,
			mainImageOriginal:
				mainImageOriginal,
			mainImageOutput:
				mainImageOutput,
			mainImagePreview:
				ImagePreview(url: url),
			auxiliaryResults:
				auxiliaryResults
		)
	}
}
