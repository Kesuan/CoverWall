import Foundation

struct ITunesSearchService: Sendable {
    private static let country = "US"

    struct SearchOutcome: Sendable {
        let albums: [ITunesResult]
        let songs: [ITunesResult]
    }

    func search(
        term: String,
        limit: Int = 25
    ) async throws -> SearchOutcome {
        async let albums = searchEntity(term: term, entity: "album", limit: limit)
        async let songs = searchEntity(term: term, entity: "song", limit: limit)
        let (albumResults, songResults) = try await (albums, songs)
        return SearchOutcome(albums: albumResults, songs: songResults)
    }

    func searchEntity(
        term: String,
        entity: String,
        limit: Int = 25
    ) async throws -> [ITunesResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: Self.country),
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        return decoded.results
    }

    func downloadArtwork(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
