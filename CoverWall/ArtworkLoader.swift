import CoreGraphics
import Foundation
import ImageIO

enum ArtworkLoader {
    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true
        ] as CFDictionary)
    }

    static func cgImage(from url: URL) async throws -> CGImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = cgImage(from: data) else {
            throw ArtworkError.invalidImage
        }
        return image
    }
}

enum ArtworkError: Error, LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "error_invalid_image")
        }
    }
}
