//
//  ContentView.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO

import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct ContentView: View {
	@State private var message:String = "Drop HEIC files here"
	@State private var overwrite:Bool = false

	var body: some View {
		VStack(spacing: 16) {

			Toggle(
				"Overwrite original files",
				isOn: $overwrite
			)

			Text(message)
				.multilineTextAlignment(.center)

		}
		.padding()
		.frame(width: 350, height: 180)

		.onDrop(of: [.fileURL], isTargeted: nil) { providers in

			for provider in providers {

				provider.loadItem(
					forTypeIdentifier: UTType.fileURL.identifier
				) { item, error in

					guard
						let data = item as? Data,
						let sourceURL =
							URL(dataRepresentation: data, relativeTo: nil)
					else {
						return
					}


					do {

						let finalURL: URL

						if overwrite {

							let tempURL =
								sourceURL
									.deletingLastPathComponent()
									.appendingPathComponent(
										sourceURL.lastPathComponent + ".tmp.heic"
									)

							try resizeHEIC(
								from: sourceURL,
								to: tempURL
							)

							try FileManager.default.replaceItemAt(
								sourceURL,
								withItemAt: tempURL
							)

							finalURL = sourceURL

						} else {

							finalURL =
								sourceURL
									.deletingPathExtension()
									.appendingPathExtension(
										"x0.5.heic"
									)

							try resizeHEIC(
								from: sourceURL,
								to: finalURL
							)
						}


						DispatchQueue.main.async {
							message =
							"Done:\n\(finalURL.lastPathComponent)"
						}


					} catch {

						DispatchQueue.main.async {
							message =
							"Error:\n\(error.localizedDescription)"
						}

					}
				}
			}

			return true
		}
	}
}


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
