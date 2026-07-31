//
//  ContentView.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import SwiftUI
import UniformTypeIdentifiers


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
