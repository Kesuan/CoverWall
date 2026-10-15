import SwiftUI

struct ContentView: View {
    @State private var searchModel = SearchViewModel()
    @State private var studioModel = WallpaperStudioViewModel()
    @State private var selection: ITunesResult?
    @State private var fullScreenResult: WallpaperResult?

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            SearchSidebar(model: searchModel, selection: $selection)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
        } detail: {
            StudioDetail(
                studio: studioModel,
                selection: selection,
                fullScreenResult: $fullScreenResult
            )
        }
        .frame(minWidth: 1100, minHeight: 720)
        .toolbar(fullScreenResult == nil ? .automatic : .hidden, for: .windowToolbar)
        .overlay {
            if let fullScreenResult {
                FullscreenPreview(
                    result: fullScreenResult,
                    onClose: { self.fullScreenResult = nil },
                    suggestedFileName: studioModel.suggestedFileName
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: fullScreenResult?.id)
        .onExitCommand {
            fullScreenResult = nil
        }
        #else
        NavigationStack {
            SearchList(model: searchModel, selection: $selection)
                .navigationDestination(item: $selection) { item in
                    StudioDetail(
                        studio: studioModel,
                        selection: item,
                        fullScreenResult: $fullScreenResult
                    )
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
                }
        }
        .fullScreenCover(item: $fullScreenResult) { result in
            FullscreenPreview(
                result: result,
                onClose: { fullScreenResult = nil },
                suggestedFileName: studioModel.suggestedFileName
            )
        }
        #endif
    }
}

// MARK: - Search (macOS sidebar)

#if os(macOS)
private struct SearchSidebar: View {
    @Bindable var model: SearchViewModel
    @Binding var selection: ITunesResult?

    var body: some View {
        SearchSidebarBody(model: model, selection: $selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .searchable(
                text: $model.searchTerm,
                placement: .sidebar,
                prompt: Text("search_placeholder")
            )
            .autocorrectionDisabled()
            .onSubmit(of: .search) {
                Task { await model.runSearch() }
            }
            .task { await model.loadFeaturedAlbums() }
    }
}

/// Keeps previous results on screen while a live search is in flight
/// (Apple Music behavior — no full-screen spinner flicker on every keystroke).
private struct SearchSidebarBody: View {
    let model: SearchViewModel
    @Binding var selection: ITunesResult?

    var body: some View {
        Group {
            if model.isSearching && !model.hasResults {
                ProgressView(String(localized: "search_in_progress"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, !model.hasResults {
                SearchFailedView(message: error)
            } else if model.hasResults {
                List(selection: $selection) {
                    if !model.albums.isEmpty {
                        Section(String(localized: "section_albums")) {
                            ForEach(model.albums) { album in
                                ResultRow(result: album)
                                    .tag(album)
                            }
                        }
                    }
                    if !model.songs.isEmpty {
                        Section(String(localized: "section_songs")) {
                            ForEach(model.songs) { song in
                                ResultRow(result: song)
                                    .tag(song)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                FeaturedSidebarContent(model: model, selection: $selection)
            }
        }
    }
}
#endif

// MARK: - Shared search chrome

private struct SearchFailedView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "search_failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeaturedSidebarContent: View {
    let model: SearchViewModel
    @Binding var selection: ITunesResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("featured_title")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Button {
                        Task { await model.refreshFeaturedAlbums() }
                    } label: {
                        if model.isLoadingFeatured {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isLoadingFeatured)
                    .help(String(localized: "featured_refresh"))
                }

                if !model.featuredAlbums.isEmpty {
                    FeaturedAlbumsGrid(albums: model.featuredAlbums) { album in
                        selection = album
                    }
                } else if model.isLoadingFeatured {
                    HStack {
                        Spacer()
                        ProgressView(String(localized: "featured_loading"))
                        Spacer()
                    }
                    .padding(.top, 24)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.house")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("featured_failed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - iOS search list

#if os(iOS)
private struct SearchList: View {
    @Bindable var model: SearchViewModel
    @Binding var selection: ITunesResult?

    var body: some View {
        Group {
            if model.isSearching && !model.hasResults {
                VStack {
                    Spacer()
                    ProgressView(String(localized: "search_in_progress"))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, !model.hasResults {
                SearchFailedView(message: error)
            } else if model.hasResults {
                List {
                    if !model.albums.isEmpty {
                        Section(String(localized: "section_albums")) {
                            ForEach(model.albums) { album in
                                SearchResultButton(result: album) {
                                    selection = album
                                }
                            }
                        }
                    }
                    if !model.songs.isEmpty {
                        Section(String(localized: "section_songs")) {
                            ForEach(model.songs) { song in
                                SearchResultButton(result: song) {
                                    selection = song
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
            } else if !model.searchTerm.isEmpty {
                ContentUnavailableView(
                    String(localized: "search_empty"),
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            } else {
                featuredSection
            }
        }
        .navigationTitle("app_title")
        .searchable(
            text: $model.searchTerm,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("search_placeholder")
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            Task { await model.runSearch() }
        }
        .task { await model.loadFeaturedAlbums() }
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !model.featuredAlbums.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("featured_title")
                        .font(.title3.weight(.bold))
                    FeaturedAlbumsGrid(albums: model.featuredAlbums) { album in
                        selection = album
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .refreshable { await model.refreshFeaturedAlbums() }
        } else if model.isLoadingFeatured {
            VStack(spacing: 12) {
                ProgressView()
                Text("featured_loading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 24)
        } else {
            ScrollView {
                ContentUnavailableView {
                    Label(String(localized: "search_idle_title"), systemImage: "music.note.house")
                } description: {
                    Text(
                        model.featuredFailed
                            ? String(localized: "featured_failed")
                            : String(localized: "search_idle_hint")
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
            }
            .refreshable { await model.refreshFeaturedAlbums() }
        }
    }
}

/// Full-width tappable row with a Music-style pressed highlight.
private struct SearchResultButton: View {
    let result: ITunesResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ResultRow(result: result)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SearchRowButtonStyle())
        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        .listRowSeparator(.hidden)
    }
}

private struct SearchRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.primary.opacity(0.09) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
#endif

// MARK: - Featured albums

private struct FeaturedAlbumsGrid: View {
    let albums: [ITunesResult]
    let onSelect: (ITunesResult) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]
        }
        #endif
        return [GridItem(.adaptive(minimum: 96, maximum: 160), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(albums) { album in
                Button {
                    onSelect(album)
                } label: {
                    FeaturedAlbumCell(album: album)
                }
                .buttonStyle(.pressFeedback)
            }
        }
    }
}

private struct FeaturedAlbumCell: View {
    let album: ITunesResult

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isHovered = false

    private var usesLargeLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ArtworkImage(url: album.artworkURL(size: 600))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .cardHairline(cornerRadius: 12)
                .shadow(
                    color: .black.opacity(isHovered ? 0.28 : 0.14),
                    radius: isHovered ? 14 : 7,
                    y: isHovered ? 7 : 3
                )
                .scaleEffect(isHovered ? 1.04 : 1)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        isHovered = hovering
                    }
                }

            Text(album.title)
                .font(usesLargeLayout ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(1)
            Text(album.artistName)
                .font(usesLargeLayout ? .footnote : .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Shared row

struct ResultRow: View {
    let result: ITunesResult

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: result.artworkURL(size: 200))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .cardHairline(cornerRadius: 10)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(result.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
