import Foundation
import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    /// Any edit schedules a debounced live search, Apple-Music style:
    /// typing pauses briefly before querying; clearing the term restores discovery.
    var searchTerm = "" {
        didSet {
            if searchTerm != oldValue { scheduleSearch() }
        }
    }
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
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    var hasResults: Bool {
        !albums.isEmpty || !songs.isEmpty
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchGeneration += 1
            albums = []
            songs = []
            errorMessage = nil
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    /// Immediate search (keyboard submit). Cancels any pending debounced search.
    /// Stale responses from superseded queries are dropped via the generation counter.
    func runSearch() async {
        searchTask?.cancel()
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        errorMessage = nil

        do {
            let outcome = try await service.search(term: term)
            guard generation == searchGeneration, !Task.isCancelled else { return }
            albums = outcome.albums
            songs = outcome.songs
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
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
