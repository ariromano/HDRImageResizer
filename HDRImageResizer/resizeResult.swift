//
//  resizeResult.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 8/1/26.
//

import Foundation


struct PixelDimensions: Equatable {
	let width: Int
	let height: Int

	var description: String {
		"\(width) × \(height)"
	}
}


enum AuxiliaryMapResult {
	case absent
	case discarded(original: PixelDimensions)
	case resized(
		original: PixelDimensions,
		output: PixelDimensions
	)
	case retainedUnchanged(
		original: PixelDimensions,
		reason: String
	)

	var summary: String {
		switch self {
		case .absent:
			return "Not present"

		case .discarded(let original):
			return "\(original.description) → discarded"

		case .resized(let original, let output):
			return "\(original.description) → \(output.description)"

		case .retainedUnchanged(let original, _):
			return "\(original.description) → unchanged"
		}
	}
}


struct HEICResizeResult {
	let fileName: String
	let mainImageOriginal: PixelDimensions
	let mainImageOutput: PixelDimensions
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
}
