import Foundation
import ImageIO
import UniformTypeIdentifiers


guard CommandLine.arguments.count == 2 else {
	print("Usage:")
	print("    swift dumpGainMap.swift image.heic")
	exit(1)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])


// MARK: - ffprobe

func runFFProbe(_ url: URL) {

	print("\nFFmpeg / HEVC inspection")
	print("------------------------")

	let process = Process()
	let pipe = Pipe()

	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = [
		"ffprobe",
		"-v",
		"quiet",
		"-print_format",
		"json",
		"-show_streams",
		"-show_format",
		url.path
	]

	process.standardOutput = pipe

	do {
		try process.run()
	} catch {
		print("""
		
		Error: ffprobe was not found.

		Install FFmpeg, for example:
			brew install ffmpeg
		
		or make sure ffprobe is available in your PATH.
		""")
		return
	}

	let data = pipe.fileHandleForReading.readDataToEndOfFile()

	guard
		let json = try? JSONSerialization.jsonObject(
			with: data
		) as? [String: Any]
	else {
		print("Could not parse ffprobe JSON")
		return
	}


	if let format = json["format"] as? [String: Any],
	   let brands = format["tags"] as? [String: Any] {

		if let compatible = brands["compatible_brands"] {
			print("HEIF brands:")
			print("  \(compatible)")

			if "\(compatible)".contains("tmap") {
				print("  ⚠ HEIF tone map (tmap) item detected")
			}
		}
	}


	guard let streams = json["streams"] as? [[String: Any]]
	else {
		return
	}


	for (index, stream) in streams.enumerated() {

		guard
			let codec = stream["codec_name"] as? String
		else {
			continue
		}

		print("\nStream \(index)")
		print("-----------")
		print("Codec:          \(codec)")

		if let profile = stream["profile"] {
			print("Profile:        \(profile)")
		}

		if let pixFmt = stream["pix_fmt"] as? String {

			print("Pixel format:   \(pixFmt)")

			let description = describePixelFormat(pixFmt)

			print("Sampling:       \(description.sampling)")
			print("Bit depth:      \(description.depth)")
		}

		if let value = stream["color_range"] {
			print("Range:          \(value)")
		}

		if let value = stream["color_primaries"] {
			print("Primaries:      \(value)")
		}

		if let value = stream["color_transfer"] {
			print("Transfer:       \(value)")
		}

		if let value = stream["color_space"] {
			print("Matrix:         \(value)")
		}

		if let width = stream["width"],
		   let height = stream["height"] {

			print("Resolution:     \(width) × \(height)")
		}
	}
}


func describePixelFormat(
	_ format: String
) -> (sampling: String, depth: String) {

	switch format {

	case "yuv420p":
		return ("4:2:0", "8-bit")

	case "yuv420p10le":
		return ("4:2:0", "10-bit")

	case "yuv422p10le":
		return ("4:2:2", "10-bit")

	case "yuv444p10le":
		return ("4:4:4", "10-bit")

	case "rgb24":
		return ("RGB", "8-bit")

	case "rgba64le":
		return ("RGBA", "16-bit")

	default:
		return ("Unknown", format)
	}
}


runFFProbe(url)


// MARK: - ImageIO inspection


guard let source =
	CGImageSourceCreateWithURL(
		url as CFURL,
		nil
	)
else {
	fatalError("Could not open image")
}


let imageCount = CGImageSourceGetCount(source)

print("\n\nImages in container: \(imageCount)")


func printDictionary(
	_ dictionary: [CFString: Any],
	indent: String = ""
) {

	for (key, value) in dictionary.sorted(by: {
		"\($0.key)" < "\($1.key)"
	}) {

		print("\(indent)\(key): \(value)")

		if let nested = value as? [CFString: Any] {
			printDictionary(
				nested,
				indent: indent + "  "
			)
		}
	}
}


for imageIndex in 0..<imageCount {

	print("\nImage \(imageIndex)")
	print("----------------")


	if let properties =
		CGImageSourceCopyPropertiesAtIndex(
			source,
			imageIndex,
			nil
		) as? [CFString: Any] {

		printDictionary(properties)
	}


	if let image =
		CGImageSourceCreateImageAtIndex(
			source,
			imageIndex,
			nil
		) {

		print("""
		
		Decoded CGImage:
			width: \(image.width)
			height: \(image.height)
			bits/component: \(image.bitsPerComponent)
			bits/pixel: \(image.bitsPerPixel)
			bitmapInfo: \(image.bitmapInfo)
			alphaInfo: \(image.alphaInfo)
		""")

		if let colorSpace = image.colorSpace {
			print("\tColor space:", colorSpace)
		}
	}


	if let gainMap =
		CGImageSourceCopyAuxiliaryDataInfoAtIndex(
			source,
			imageIndex,
			kCGImageAuxiliaryDataTypeHDRGainMap
		) as? [CFString: Any] {

		print("\nHDR Gain Map found!")
		print("-----------------")

		printDictionary(gainMap)


		if let data =
			gainMap[kCGImageAuxiliaryDataInfoData] as? Data {

			print("\nGain map data size: \(data.count) bytes")

			let bytes = [UInt8](data.prefix(64))

			print("First bytes:")

			for (i, byte) in bytes.enumerated() {

				if i % 16 == 0 {
					print(
						String(format: "\n%04X: ", i),
						terminator: ""
					)
				}

				print(
					String(format: "%02X ", byte),
					terminator: ""
				)
			}

			print("\n")
		}

	} else {

		print("\nNo HDR gain map found")
	}
}
