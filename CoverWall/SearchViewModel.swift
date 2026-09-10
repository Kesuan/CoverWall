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
    var statusKey: LocalizedStringKey = "search_idle_hint"

    private let service = ITunesSearchService()

    var hasResults: Bool {
        !albums.isEmpty || !songs.isEmpty
    }

    func runSearch() async {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        statusKey = "search_in_progress"

        do {
            let outcome = try await service.search(term: term)
            albums = outcome.albums
            songs = outcome.songs
            if outcome.albums.isEmpty && outcome.songs.isEmpty {
                statusKey = "search_empty"
            } else {
                statusKey = "search_result_count"
            }
        } catch {
            albums = []
            songs = []
            errorMessage = error.localizedDescription
            statusKey = "search_failed"
        }

        isSearching = false
    }
}
