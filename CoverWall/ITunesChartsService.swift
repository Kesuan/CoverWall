import Foundation

struct ITunesChartsService: Sendable {
    private static let country = "US"

    /// Verified non-empty main music genres for the legacy top-albums feed.
    static let discoverGenreIDs = [2, 5, 6, 7, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 24, 1289]

    struct FeedResponse: Decodable, Sendable {
        let feed: Feed
    }

    struct Feed: Decodable, Sendable {
        let results: [FeedItem]
    }

    struct FeedItem: Decodable, Sendable {
        let id: String
        let name: String
        let artistName: String
        let artworkUrl100: String
        let releaseDate: String?
    }

    struct LegacyFeedResponse: Decodable, Sendable {
        let feed: LegacyFeed
    }

    struct LegacyFeed: Decodable, Sendable {
        let entry: [LegacyEntry]

        private enum CodingKeys: String, CodingKey {
            case entry
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.entry) else {
                entry = []
                return
            }
            if let many = try? container.decode([LegacyEntry].self, forKey: .entry) {
                entry = many
            } else if let one = try? container.decode(LegacyEntry.self, forKey: .entry) {
                entry = [one]
            } else {
                entry = []
            }
        }
    }

    struct LegacyEntry: Decodable, Sendable {
        struct LabeledValue: Decodable, Sendable {
            let label: String
        }

        struct Identifier: Decodable, Sendable {
            struct Attributes: Decodable, Sendable {
                let imID: String

                private enum CodingKeys: String, CodingKey {
                    case imID = "im:id"
                }
            }

            let attributes: Attributes
        }

        let name: LabeledValue
        let artist: LabeledValue
        let image: [LabeledValue]
        let releaseDate: LabeledValue?
        let id: Identifier

        private enum CodingKeys: String, CodingKey {
            case name = "im:name"
            case artist = "im:artist"
            case image = "im:image"
            case releaseDate = "im:releaseDate"
            case id
        }
    }

    func topAlbums(
        country: String = Self.country,
        limit: Int = 25
    ) async throws -> [ITunesResult] {
        var components = URLComponents(string: "https://rss.marketingtools.apple.com")!
        components.path = "/api/v2/\(country)/music/most-played/\(limit)/albums.json"
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(FeedResponse.self, from: data)
        return decoded.feed.results.map { item in
            ITunesResult(
                trackName: nil,
                collectionName: item.name,
                artistName: item.artistName,
                artworkUrl100: item.artworkUrl100,
                collectionId: Int(item.id),
                trackId: nil,
                releaseDate: item.releaseDate
            )
        }
    }

    func genreTopAlbums(
        genreId: Int,
        limit: Int = 100
    ) async throws -> [ITunesResult] {
        var components = URLComponents(string: "https://itunes.apple.com")!
        components.path = "/\(Self.country)/rss/topalbums/limit=\(limit)/genre=\(genreId)/json"
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(LegacyFeedResponse.self, from: data)
        return decoded.feed.entry.compactMap(makeResult(from:))
    }

    /// Merge the daily chart with one random genre chart, then sample.
    /// A single failed source is tolerated; only both failing is an error.
    func randomFeaturedAlbums(
        genreId: Int,
        limit: Int = 25,
        country: String = Self.country
    ) async throws -> [ITunesResult] {
        async let chart = topAlbums(country: country, limit: 100)
        async let genre = genreTopAlbums(genreId: genreId)

        let chartAlbums = try? await chart
        let genreAlbums = try? await genre

        var pool: [ITunesResult] = []
        if let chartAlbums {
            pool += chartAlbums
        }
        if let genreAlbums {
            pool += genreAlbums
        }
        guard !pool.isEmpty else {
            throw URLError(.cannotLoadFromNetwork)
        }

        var seen = Set<Int>()
        let unique = pool.filter { album in
            guard let collectionId = album.collectionId else { return false }
            return seen.insert(collectionId).inserted
        }
        return Array(unique.shuffled().prefix(limit))
    }

    private func makeResult(from entry: LegacyEntry) -> ITunesResult? {
        guard let artwork = entry.image.last?.label else { return nil }
        let normalizedArtwork: String
        if let slash = artwork.lastIndex(of: "/") {
            normalizedArtwork = String(artwork[..<slash]) + "/100x100bb.jpg"
        } else {
            normalizedArtwork = artwork
        }
        return ITunesResult(
            trackName: nil,
            collectionName: entry.name.label,
            artistName: entry.artist.label,
            artworkUrl100: normalizedArtwork,
            collectionId: Int(entry.id.attributes.imID),
            trackId: nil,
            releaseDate: entry.releaseDate?.label
        )
    }
}
