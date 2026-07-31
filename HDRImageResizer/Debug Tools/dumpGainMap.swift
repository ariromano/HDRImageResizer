import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
	print("Usage:")
	print("    swift dumpHEIC.swift image.heic")
	exit(1)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])

guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
	fatalError("Could not open image")
}

let imageCount = CGImageSourceGetCount(source)

print("Images in container: \(imageCount)")

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

	if let image = CGImageSourceCreateImageAtIndex(
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

			print("\n Gain map data size: \(data.count) bytes")

			let bytes = [UInt8](data.prefix(64))

			print("First bytes:")

			for (i, byte) in bytes.enumerated() {

				if i % 16 == 0 {
					print(String(format: "\n%04X: ", i),
						  terminator: "")
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
