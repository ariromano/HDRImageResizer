//
//  AuxiliaryMapOptions.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 8/1/26.
//

import Foundation
import ImageIO

enum AuxiliaryMapKind: String, CaseIterable, Identifiable {

	case hdrGainMap
	case depthDisparity
	case portraitEffectsMatte

	var id: String {
		rawValue
	}

	var displayName: String {
		switch self {
		case .hdrGainMap:
			return "HDR gain map"

		case .depthDisparity:
			return "Depth / disparity map"

		case .portraitEffectsMatte:
			return "Portrait-effects matte"
		}
	}

	// For depth we prefer a true depth map, but fall back to disparity if that's what the file contains
	var possibleImageIOTypes: [CFString] {
		switch self {

		case .hdrGainMap:
			return [
				kCGImageAuxiliaryDataTypeHDRGainMap
			]

		case .depthDisparity:
			return [
				kCGImageAuxiliaryDataTypeDepth,
				kCGImageAuxiliaryDataTypeDisparity
			]

		case .portraitEffectsMatte:
			return [
				kCGImageAuxiliaryDataTypePortraitEffectsMatte
			]
		}
	}
}


struct AuxiliaryMapOption: Identifiable {

	let kind: AuxiliaryMapKind

	var enabled: Bool

	var scale: CGFloat

	var id: AuxiliaryMapKind {
		kind
	}
}


extension AuxiliaryMapOption {

	static let defaults: [AuxiliaryMapOption] = [
		AuxiliaryMapOption(
			kind: .hdrGainMap,
			enabled: true,
			scale: 0.50
		),

		AuxiliaryMapOption(
			kind: .depthDisparity,
			enabled: true,
			scale: 0.50
		),

		AuxiliaryMapOption(
			kind: .portraitEffectsMatte,
			enabled: true,
			scale: 0.50
		)
	]
}
