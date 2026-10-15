import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

#if canImport(Photos)
import Photos
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

enum PhotoExportService {
    enum ExportError: Error, LocalizedError {
        case encodeFailed
        case permissionDenied
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .encodeFailed: return String(localized: "error_encode_failed")
            case .permissionDenied: return String(localized: "error_photo_permission")
            case .saveFailed: return String(localized: "error_save_failed")
            }
        }
    }

    static func jpegData(from image: CGImage, quality: CGFloat = 0.95) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.encodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.encodeFailed
        }
        return data as Data
    }

    static func saveToPhotoLibrary(_ image: CGImage) async throws {
        try await saveToPhotoLibrary(try jpegData(from: image))
    }

    static func saveToPhotoLibrary(_ data: Data) async throws {
        try await requestAddOnlyPermission()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(
                    with: .photo,
                    data: data,
                    options: nil
                )
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportError.saveFailed)
                }
            })
        }
    }

    private static func requestAddOnlyPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                throw ExportError.permissionDenied
            }
        default:
            throw ExportError.permissionDenied
        }
    }
}

#if os(macOS)
extension PhotoExportService {
    static func savePanelWrite(_ image: CGImage, suggestedName: String) throws {
        try savePanelWrite(try jpegData(from: image), suggestedName: suggestedName)
    }

    static func savePanelWrite(_ data: Data, suggestedName: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try data.write(to: target)
    }
}
#endif
