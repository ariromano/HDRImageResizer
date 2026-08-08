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
		"-v", "quiet",
		"-print_format", "json",
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
		""")
		return
	}

	let data = pipe.fileHandleForReading.readDataToEndOfFile()

	guard
		let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
	else {
		print("Could not parse ffprobe JSON")
		return
	}

	if let format = json["format"] as? [String: Any],
	   let tags = format["tags"] as? [String: Any],
	   let brands = tags["compatible_brands"] {

		print("HEIF brands:")
		print("  \(brands)")

		if "\(brands)".contains("tmap") {
			print(" HEIF tone map (tmap) item detected")
		}
	}

	guard let streams = json["streams"] as? [[String: Any]] else {
		return
	}

	struct Group {
		var count = 0
		var codec = ""
		var profile = ""
		var pixFmt = ""
		var sampling = ""
		var depth = ""
		var width = 0
		var height = 0
		var range = ""
		var primaries = ""
		var transfer = ""
		var matrix = ""
	}

	var groups: [String: Group] = [:]

	for stream in streams {

		let codec = stream["codec_name"] as? String ?? "?"
		let profile = stream["profile"] as? String ?? ""
		let pixFmt = stream["pix_fmt"] as? String ?? "?"

		let width = stream["width"] as? Int ?? 0
		let height = stream["height"] as? Int ?? 0

		let desc = describePixelFormat(pixFmt)

		let key = "\(codec)|\(pixFmt)|\(width)x\(height)"

		if groups[key] == nil {

			groups[key] = Group(
				count: 0,
				codec: codec,
				profile: profile,
				pixFmt: pixFmt,
				sampling: desc.sampling,
				depth: desc.depth,
				width: width,
				height: height,
				range: stream["color_range"] as? String ?? "",
				primaries: stream["color_primaries"] as? String ?? "",
				transfer: stream["color_transfer"] as? String ?? "",
				matrix: stream["color_space"] as? String ?? ""
			)
		}

		groups[key]!.count += 1
	}

	func printGroup(_ title: String, _ group: Group) {

		print("\n\(title)")
		print(String(repeating: "-", count: title.count))

		print("Count:          \(group.count)")
		print("Codec:          \(group.codec)")
		print("Profile:        \(group.profile)")
		print("Resolution:     \(group.width) × \(group.height)")
		print("Pixel format:   \(group.pixFmt)")
		print("Sampling:       \(group.sampling)")
		print("Bit depth:      \(group.depth)")

		if !group.range.isEmpty {
			print("Range:          \(group.range)")
		}

		if !group.primaries.isEmpty {
			print("Primaries:      \(group.primaries)")
		}

		if !group.transfer.isEmpty {
			print("Transfer:       \(group.transfer)")
		}

		if !group.matrix.isEmpty {
			print("Matrix:         \(group.matrix)")
		}
	}

	// Largest colour image(s)
	let colourGroups = groups.values
		.filter { !$0.pixFmt.contains("gray") }
		.sorted {
			($0.width * $0.height) >
			($1.width * $1.height)
		}

	if let primary = colourGroups.first {
		printGroup("Primary image tiles", primary)
	}

	// Remaining colour images
	if colourGroups.count > 1 {

		for group in colourGroups.dropFirst() {
			printGroup("Other colour images", group)
		}
	}

	// Grayscale images
	let grayGroups = groups.values
		.filter { $0.pixFmt.contains("gray") }
		.sorted {
			($0.width * $0.height) >
			($1.width * $1.height)
		}

	if !grayGroups.isEmpty {

		for group in grayGroups {
			printGroup("Grayscale auxiliary images", group)
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
