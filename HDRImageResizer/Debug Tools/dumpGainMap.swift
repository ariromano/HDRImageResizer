import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 1 else {
    print("Usage: dumpGainMap.swift file.heic")
    exit(1)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])

guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
    print("Could not open image")
    exit(1)
}

let index = 0

if let aux =
    CGImageSourceCopyAuxiliaryDataInfoAtIndex(
        source,
        index,
        kCGImageAuxiliaryDataTypeHDRGainMap
    ) as? [CFString: Any]
{
    print("HDR gain map found")

    for (key, value) in aux {
        print("\(key): \(value)")
    }

} else {
    print("No HDR gain map found")
}