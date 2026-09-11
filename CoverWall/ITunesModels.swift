import Foundation

struct ITunesSearchResponse: Decodable, Sendable {
    let resultCount: Int
    let results: [ITunesResult]
}

struct ITunesResult: Decodable, Hashable, Identifiable, Sendable {
    let trackName: String?
    let collectionName: String?
    let artistName: String
    let artworkUrl100: String
    let collectionId: Int?
    let trackId: Int?
    let releaseDate: String?

    var id: String {
        "\(collectionId ?? 0)-\(trackId ?? 0)-\(title)"
    }

    var title: String {
        trackName ?? collectionName ?? String(localized: "unknown_title")
    }

    var isAlbum: Bool {
        trackName == nil && collectionName != nil
    }

    /// Replace the 100×100 thumbnail URL with a requested pixel size.
    /// The CDN caps at the original artwork resolution and will not upscale.
    func artworkURL(size: Int) -> URL? {
        let replaced = artworkUrl100
            .replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb")
        return URL(string: replaced)
    }

    /// Wallpaper-grade source artwork.
    func highResArtworkURL(size: Int = 3000) -> URL? {
        artworkURL(size: size)
    }
}
