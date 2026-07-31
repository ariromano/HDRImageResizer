//
//  ContentView.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct ContentView: View {
	@State private var message = "Drop HEIC"

	var body: some View {
		VStack {
			Text(message)
				.multilineTextAlignment(.center)
				.padding()
		}
		.frame(width: 300, height: 150)
		.onDrop(of: [.fileURL], isTargeted: nil) { providers in

			for provider in providers {
				provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in

					guard
						let data = item as? Data,
						let sourceURL = URL(dataRepresentation: data, relativeTo: nil)
					else {
						DispatchQueue.main.async {
							message = "Could not read dropped file"
						}
						return
					}

					do {
						let outputURL = FileManager.default.homeDirectoryForCurrentUser
							.appendingPathComponent("Desktop")
							.appendingPathComponent(
								sourceURL.deletingPathExtension().lastPathComponent
								+ ".copy.heic"
							)

						print("Input:", sourceURL.path)
						print("Output:", outputURL.path)

						try copyHEIC(
							from: sourceURL,
							to: outputURL
						)

						DispatchQueue.main.async {
							message = "Created:\n\(outputURL.lastPathComponent)"
						}

					} catch {
						print(error)

						DispatchQueue.main.async {
							message = "Error:\n\(error.localizedDescription)"
						}
					}
				}
			}

			return true
		}
	}
}


func copyHEIC(from inputURL: URL, to outputURL: URL) throws {

	guard let source = CGImageSourceCreateWithURL(
		inputURL as CFURL,
		nil
	) else {
		throw NSError(domain: "HDRCopy", code: 1)
	}

	guard let destination = CGImageDestinationCreateWithURL(
		outputURL as CFURL,
		UTType.heic.identifier as CFString,
		1,
		nil
	) else {
		throw NSError(domain: "HDRCopy", code: 2)
	}


	let imageIndex = 0


	// (test) copy  main image
	CGImageDestinationAddImageFromSource(
		destination,
		source,
		imageIndex,
		nil
	)


	// Copy HDR gain map
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
		else {
			print("No auxiliary data:", type)
		}
	}


	guard CGImageDestinationFinalize(destination)
	else {
		throw NSError(domain: "HDRCopy", code: 3)
	}
}
