import Foundation
import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    var searchTerm = ""
    var albums: [ITunesResult] = []
    var songs: [ITunesResult] = []
    var isSearching = false
    var errorMessage: String?

    var featuredAlbums: [ITunesResult] = []
    var isLoadingFeatured = false
    var featuredFailed = false

    private let service = ITunesSearchService()
    private let chartsService = ITunesChartsService()
    private var lastFeaturedGenreId: Int?

    var hasResults: Bool {
        !albums.isEmpty || !songs.isEmpty
    }

    func runSearch() async {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        isSearching = true
        errorMessage = nil

        do {
            let outcome = try await service.search(term: term)
            albums = outcome.albums
            songs = outcome.songs
        } catch {
            albums = []
            songs = []
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    func loadFeaturedAlbums() async {
        guard featuredAlbums.isEmpty, !isLoadingFeatured else { return }
        await fetchFeaturedAlbums()
    }

    func refreshFeaturedAlbums() async {
        guard !isLoadingFeatured else { return }
        await fetchFeaturedAlbums()
    }

    private func fetchFeaturedAlbums() async {
        isLoadingFeatured = true
        featuredFailed = false
        let genreId = Self.randomGenreID(excluding: lastFeaturedGenreId)
        lastFeaturedGenreId = genreId
        do {
            featuredAlbums = try await chartsService.randomFeaturedAlbums(genreId: genreId)
        } catch {
            featuredFailed = featuredAlbums.isEmpty
        }
        isLoadingFeatured = false
    }

    private static func randomGenreID(excluding excluded: Int?) -> Int {
        let candidates = ITunesChartsService.discoverGenreIDs.filter { $0 != excluded }
        return candidates.randomElement() ?? ITunesChartsService.discoverGenreIDs[0]
    }
}
