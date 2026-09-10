// Generates README demo wallpapers by invoking the app's WallpaperGenerator.
// Build & run from repo root:
//   swiftc -O -o /tmp/cw-examples \
//     CoverWall/Models.swift CoverWall/WallpaperGenerator.swift \
//     Tools/GenerateReadmeExamples/main.swift
//   /tmp/cw-examples Docs/Examples

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func loadImage(at url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "CoverWallExamples", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to load image at \(url.path)"
        ])
    }
    return image
}

func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "CoverWallExamples", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Failed to create destination for \(url.path)"
        ])
    }
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality
    ]
    CGImageDestinationAddImage(dest, image, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "CoverWallExamples", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Failed to write \(url.path)"
        ])
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: GenerateReadmeExamples <output-directory> [source-image]\n", stderr)
    exit(64)
}

let outputDir = URL(fileURLWithPath: args[1], isDirectory: true)
let sourceURL: URL
if args.count >= 3 {
    sourceURL = URL(fileURLWithPath: args[2])
} else {
    sourceURL = outputDir.appendingPathComponent("source-cover.jpg")
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let source = try loadImage(at: sourceURL)
print("Source: \(source.width)×\(source.height) → \(sourceURL.path)")

for device in DeviceProfile.allCases {
    let results = WallpaperGenerator.generate(source: source, for: device)
    for result in results {
        let name = "\(device.rawValue)-\(result.algorithm.rawValue).jpg"
        let out = outputDir.appendingPathComponent(name)
        try writeJPEG(result.image, to: out, quality: 0.88)
        print("  wrote \(name)  \(result.image.width)×\(result.image.height)")
    }
}

print("Done.")
