//
//  ContentView.swift
//  HDRImageResizer
//
//  Created by Ari Romano McBride on 7/31/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit


struct ContentView: View {

	@State private var message =
		"Drop HEIC files here"

	@State private var overwrite = false
	@State private var imageScaleIndex = 1

	@State private var auxiliaryMaps =
		AuxiliaryMapOption.defaults

	@State private var lastResult:
		HEICResizeResult?

	private let imageScales: [CGFloat] = [
		0.25,
		0.50,
		0.75
	]

	private var selectedImageScale: CGFloat {
		imageScales[imageScaleIndex]
	}


	var body: some View {
		VStack(alignment: .leading, spacing: 18) {

			Toggle(
				"Overwrite original files",
				isOn: $overwrite
			)

			Divider()

			mainImageControl

			Divider()

			HStack {
				Text("Auxiliary maps")
					.font(.headline)

				Spacer()

				if let lastResult {
					Text(lastResult.fileName)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}

			VStack(spacing: 14) {
				ForEach($auxiliaryMaps) {
					$option in

					auxiliaryMapControl(
						option: $option
					)
				}
			}

			Divider()

			Text(message)
				.frame(maxWidth: .infinity)
				.multilineTextAlignment(.center)
				.foregroundStyle(.secondary)
		}
		.padding(20)
		.frame(width: 680)
		.onDrop(
			of: [.fileURL],
			isTargeted: nil,
			perform: handleDrop
		)
	}


	// MARK: - Main image

	private var mainImageControl: some View {
		VStack(alignment: .leading, spacing: 6) {

			HStack {
				Text(
					"Main image: "
					+ "\(Int(selectedImageScale * 100))%"
				)

				Spacer()

				previewButton(
					lastResult?.mainImagePreview
				)

				resultText(
					lastResult?.mainImageSummary
				)
			}

			Slider(
				value: Binding(
					get: {
						Double(imageScaleIndex)
					},
					set: {
						imageScaleIndex =
							Int($0.rounded())
					}
				),
				in: 0...Double(
					imageScales.count - 1
				),
				step: 1
			)

			scaleLabels(imageScales)
		}
	}


	// MARK: - Auxiliary controls

	@ViewBuilder
	private func auxiliaryMapControl(
		option: Binding<AuxiliaryMapOption>
	) -> some View {

		let kind =
			option.wrappedValue.kind

		let result =
			lastResult?.result(for: kind)

		VStack(alignment: .leading, spacing: 6) {

			HStack {
				Toggle(
					kind.displayName,
					isOn: option.isEnabled
				)

				Spacer()

				previewButton(
					result?.preview
				)

				resultText(
					result?.summary
				)

				if option.wrappedValue.isEnabled {
					Text(
						"""
						\(Int(
							option.wrappedValue
								.scale * 100
						))%
						"""
					)
					.monospacedDigit()
					.foregroundStyle(.secondary)
					.frame(
						width: 42,
						alignment: .trailing
					)
				}
			}

			if option.wrappedValue.isEnabled {
				Slider(
					value: Binding(
						get: {
							Double(
								option.wrappedValue
									.scaleIndex
							)
						},
						set: {
							option.wrappedValue
								.scaleIndex =
								Int($0.rounded())
						}
					),
					in: 0...Double(
						AuxiliaryMapOption
							.availableScales
							.count - 1
					),
					step: 1
				)

				scaleLabels(
					AuxiliaryMapOption
						.availableScales
				)
			}
		}
	}


	// MARK: - Preview buttons

	@ViewBuilder
	private func previewButton(
		_ preview: ImagePreview?
	) -> some View {

		if let url = preview?.url {
			Button {
				NSWorkspace.shared.open(url)
			} label: {
				Image(systemName: "photo")
			}
			.buttonStyle(.borderless)
			.help(
				"Open \(url.lastPathComponent)"
			)
		}
	}


	// MARK: - Result text

	@ViewBuilder
	private func resultText(
		_ text: String?
	) -> some View {

		if let text {
			Text(text)
				.font(.caption)
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.frame(
					minWidth: 190,
					alignment: .trailing
				)
		}
	}


	// MARK: - Scale labels

	private func scaleLabels(
		_ scales: [CGFloat]
	) -> some View {

		HStack {
			ForEach(
				Array(scales.enumerated()),
				id: \.offset
			) { index, scale in

				Text(
					"\(Int(scale * 100))%"
				)

				if index < scales.count - 1 {
					Spacer()
				}
			}
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}


	// MARK: - Drag and drop

	private func handleDrop(
		_ providers: [NSItemProvider]
	) -> Bool {

		let imageScale =
			selectedImageScale

		let overwriteOriginals =
			overwrite

		let capturedAuxiliaryOptions =
			auxiliaryMaps

		for provider in providers {
			provider.loadItem(
				forTypeIdentifier:
					UTType.fileURL.identifier
			) { item, error in

				if let error {
					updateMessage(
						"Error:\n"
						+ error.localizedDescription
					)
					return
				}

				guard
					let data = item as? Data,
					let sourceURL = URL(
						dataRepresentation: data,
						relativeTo: nil
					)
				else {
					updateMessage(
						"""
						Error:
						Could not read dropped file.
						"""
					)
					return
				}

				do {
					let previewDirectory =
						makePreviewDirectory()

					let finalURL: URL
					let result: HEICResizeResult

					if overwriteOriginals {
						let temporaryURL =
							makeTemporaryURL(
								for: sourceURL
							)

						result = try resizeHEIC(
							from: sourceURL,
							to: temporaryURL,
							scale: imageScale,
							auxiliaryOptions:
								capturedAuxiliaryOptions,
							previewDirectory:
								previewDirectory
						)

						try FileManager.default
							.replaceItemAt(
								sourceURL,
								withItemAt:
									temporaryURL
							)

						finalURL = sourceURL

					} else {
						finalURL = makeOutputURL(
							for: sourceURL,
							scale: imageScale
						)

						result = try resizeHEIC(
							from: sourceURL,
							to: finalURL,
							scale: imageScale,
							auxiliaryOptions:
								capturedAuxiliaryOptions,
							previewDirectory:
								previewDirectory
						)
					}

					let displayedResult =
						result
							.replacingMainImagePreview(
								with: finalURL
							)

					updateResult(
						displayedResult,
						outputURL: finalURL
					)

				} catch {
					updateMessage(
						"Error:\n"
						+ error.localizedDescription
					)
				}
			}
		}

		return true
	}


	// MARK: - URLs

	private func makeOutputURL(
		for sourceURL: URL,
		scale: CGFloat
	) -> URL {

		let percentage =
			Int(scale * 100)

		let baseName =
			sourceURL
				.deletingPathExtension()
				.lastPathComponent

		return sourceURL
			.deletingLastPathComponent()
			.appendingPathComponent(
				"\(baseName)x\(percentage).heic"
			)
	}


	private func makeTemporaryURL(
		for sourceURL: URL
	) -> URL {

		sourceURL
			.deletingLastPathComponent()
			.appendingPathComponent(
				".\(UUID().uuidString).heic"
			)
	}


	private func makePreviewDirectory() -> URL {

		FileManager.default
			.temporaryDirectory
			.appendingPathComponent(
				"HDRImageResizer",
				isDirectory: true
			)
			.appendingPathComponent(
				UUID().uuidString,
				isDirectory: true
			)
	}


	// MARK: - UI updates

	private func updateResult(
		_ result: HEICResizeResult,
		outputURL: URL
	) {
		DispatchQueue.main.async {
			lastResult = result

			message =
				"Created "
				+ outputURL.lastPathComponent
		}
	}


	private func updateMessage(
		_ newMessage: String
	) {
		DispatchQueue.main.async {
			message = newMessage
		}
	}
}
