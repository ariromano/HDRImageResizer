//
//  AuxiliaryMapOptions.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 8/1/26.
//

import Foundation
import ImageIO
import CoreGraphics


enum AuxiliaryMapKind: String, CaseIterable, Identifiable {
	case hdrGainMap
	case depth
	case disparity
	case portraitEffectsMatte

	var id: Self {
		self
	}

	var displayName: String {
		switch self {
		case .hdrGainMap:
			return "HDR gain map"

		case .depth:
			return "Depth map"

		case .disparity:
			return "Disparity map"

		case .portraitEffectsMatte:
			return "Portrait-effects matte"
		}
	}

	var imageIOType: CFString {
		switch self {
		case .hdrGainMap:
			return kCGImageAuxiliaryDataTypeHDRGainMap

		case .depth:
			return kCGImageAuxiliaryDataTypeDepth

		case .disparity:
			return kCGImageAuxiliaryDataTypeDisparity

		case .portraitEffectsMatte:
			return kCGImageAuxiliaryDataTypePortraitEffectsMatte
		}
	}
}


struct AuxiliaryMapOption: Identifiable {
	let kind: AuxiliaryMapKind
	var isEnabled: Bool
	var scaleIndex: Int

	var id: AuxiliaryMapKind {
		kind
	}

	var scale: CGFloat {
		AuxiliaryMapOption.availableScales[scaleIndex]
	}

	static let availableScales: [CGFloat] = [
		0.10,
		0.25,
		0.50,
		0.75,
		1.0
	]

	static let defaults: [AuxiliaryMapOption] = [
		AuxiliaryMapOption(
			kind: .hdrGainMap,
			isEnabled: true,
			scaleIndex: 1
		),
		AuxiliaryMapOption(
			kind: .depth,
			isEnabled: true,
			scaleIndex: 1
		),
		AuxiliaryMapOption(
			kind: .disparity,
			isEnabled: true,
			scaleIndex: 1
		),
		AuxiliaryMapOption(
			kind: .portraitEffectsMatte,
			isEnabled: true,
			scaleIndex: 1
		)
	]
}
