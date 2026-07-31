//
//  ContentView.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

	@State private var message = "Drop HEIC files here"
	@State private var overwrite = false
	@State private var scaleIndex = 1

	let scales: [CGFloat] = [
		0.25,
		0.50,
		0.75	]

	var selectedScale: CGFloat {
		scales[scaleIndex]
	}

	var body: some View {
		VStack(spacing: 16) {

			Toggle(
				"Overwrite original files",
				isOn: $overwrite
			)

			VStack {
				Text(
					"Image size: \(Int(selectedScale * 100))%"
				)

				Slider(
					value: Binding(
						get: {
							Double(scaleIndex)
						},
						set: {
							scaleIndex = Int($0.rounded())
						}
					),
					in: 0...2,
					step: 1
				)

				HStack {
					Text("25%")
					Spacer()
					Text("50%")
					Spacer()
					Text("75%")
				}
				.font(.caption)
			}


			Text(message)
				.multilineTextAlignment(.center)

		}
		.padding()
		.frame(width: 380, height: 230)

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

						let scale = selectedScale

						let finalURL: URL

						if overwrite {

							let tempURL =
								sourceURL
									.deletingLastPathComponent()
									.appendingPathComponent(
										sourceURL.lastPathComponent
										+ ".tmp.heic"
									)

							try resizeHEIC(
								from: sourceURL,
								to: tempURL,
								scale: scale
							)

							try FileManager.default.replaceItemAt(
								sourceURL,
								withItemAt: tempURL
							)

							finalURL = sourceURL

						} else {

							let percentage = Int(selectedScale * 100)

							finalURL =
								sourceURL
									.deletingPathExtension()
									.appendingPathExtension(
										"x\(percentage).heic"
									)

							try resizeHEIC(
								from: sourceURL,
								to: finalURL,
								scale: scale
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
