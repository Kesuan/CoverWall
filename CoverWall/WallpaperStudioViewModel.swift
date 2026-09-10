import CoreGraphics
import Foundation
import SwiftUI

@MainActor
@Observable
final class WallpaperStudioViewModel {
    var selectedDevice: DeviceProfile = .current
    var sourceArtwork: CGImage?
    var sourceResult: ITunesResult?
    var results: [WallpaperResult] = []
    var isGenerating = false
    var isDownloading = false
    var errorMessage: String?
    var exportMessage: LocalizedStringKey?
    var isExporting = false

    private let service = ITunesSearchService()

    var suggestedFileName: String {
        guard let sourceResult else { return "CoverWall.jpg" }
        let artist = sourceResult.artistName
            .replacingOccurrences(of: "/", with: "-")
        let title = sourceResult.title
            .replacingOccurrences(of: "/", with: "-")
        return "\(artist) - \(title).jpg"
    }

    func prepare(result: ITunesResult) async {
        sourceResult = result
        errorMessage = nil
        exportMessage = nil
        results = []
        sourceArtwork = nil

        guard let url = result.highResArtworkURL() else {
            errorMessage = String(localized: "error_invalid_artwork_url")
            return
        }

        isDownloading = true
        do {
            let data = try await service.downloadArtwork(from: url)
            guard let image = ArtworkLoader.cgImage(from: data) else {
                throw ArtworkError.invalidImage
            }
            sourceArtwork = image
            isDownloading = false
            await generate()
        } catch {
            isDownloading = false
            errorMessage = error.localizedDescription
        }
    }

    func generate() async {
        guard let sourceArtwork else { return }
        let device = selectedDevice
        isGenerating = true
        errorMessage = nil

        let source = sourceArtwork
        let generated = await Task.detached(priority: .userInitiated) {
            WallpaperGenerator.generate(source: source, for: device)
        }.value

        results = generated
        isGenerating = false
    }

    func regenerateForDeviceChange() async {
        guard sourceArtwork != nil else { return }
        await generate()
    }

    func saveToPhotos(_ result: WallpaperResult) async {
        isExporting = true
        exportMessage = nil
        do {
            try await PhotoExportService.saveToPhotoLibrary(result.image)
            exportMessage = "export_saved_photos"
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }

    func jpegData(for result: WallpaperResult) -> Data? {
        try? PhotoExportService.jpegData(from: result.image)
    }

    #if os(macOS)
    func saveViaPanel(_ result: WallpaperResult) {
        do {
            try PhotoExportService.savePanelWrite(result.image, suggestedName: suggestedFileName)
            exportMessage = "export_saved_file"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif
}
