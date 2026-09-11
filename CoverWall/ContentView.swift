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
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: fullScreenResult?.id)
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
        VStack(spacing: 0) {
            SearchHeader(model: model)
            Divider()
            SearchResultsList(model: model, selection: $selection)
        }
        .background(.regularMaterial)
        .task { await model.loadFeaturedAlbums() }
    }
}
#endif

// MARK: - Shared search chrome

private struct SearchHeader: View {
    @Bindable var model: SearchViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("app_title")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("app_tagline")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("search_placeholder", text: $model.searchTerm)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        Task { await model.runSearch() }
                    }
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Button {
                    Task { await model.runSearch() }
                } label: {
                    if model.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("search_action", systemImage: "magnifyingglass")
                    }
                }
                .disabled(
                    model.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isSearching
                )
                .keyboardShortcut(.defaultAction)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
    }
}

private struct SearchResultsList: View {
    let model: SearchViewModel
    @Binding var selection: ITunesResult?

    var body: some View {
        Group {
            if !model.hasResults && !model.isSearching {
                FeaturedSidebarContent(model: model, selection: $selection)
            } else {
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
            }
        }
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
                        .font(.headline)
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
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("app_tagline")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("search_placeholder", text: $model.searchTerm)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await model.runSearch() }
                        }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Spacer()

                    Button {
                        searchFocused = false
                        Task { await model.runSearch() }
                    } label: {
                        if model.isSearching {
                            ProgressView()
                        } else {
                            Text("search_action")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.isSearching
                    )
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if model.isSearching {
                VStack {
                    Spacer()
                    ProgressView(String(localized: "search_in_progress"))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasResults {
                List {
                    if !model.albums.isEmpty {
                        Section(String(localized: "section_albums")) {
                            ForEach(model.albums) { album in
                                Button {
                                    selection = album
                                } label: {
                                    ResultRow(result: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !model.songs.isEmpty {
                        Section(String(localized: "section_songs")) {
                            ForEach(model.songs) { song in
                                Button {
                                    selection = song
                                } label: {
                                    ResultRow(result: song)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
        .task { await model.loadFeaturedAlbums() }
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !model.featuredAlbums.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("featured_title")
                        .font(.headline)
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
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FeaturedAlbumCell: View {
    let album: ITunesResult

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                    AsyncImage(url: album.artworkURL(size: 600)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
            AsyncImage(url: result.artworkURL(size: 200)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
