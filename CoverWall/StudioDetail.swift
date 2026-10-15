import SwiftUI

struct StudioDetail: View {
    @Bindable var studio: WallpaperStudioViewModel
    let selection: ITunesResult?
    @Binding var fullScreenResult: WallpaperResult?
    @State private var didLoadForSelection: ITunesResult?

    var body: some View {
        Group {
            if selection == nil {
                emptyState
            } else {
                studioBody
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .task(id: selection?.id) {
            guard let selection, didLoadForSelection?.id != selection.id else { return }
            didLoadForSelection = selection
            await studio.prepare(result: selection)
        }
        .onChange(of: studio.selectedDevice) { _, _ in
            Task { await studio.regenerateForDeviceChange() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "studio_empty_title"), systemImage: "wand.and.stars")
        } description: {
            Text(String(localized: "studio_empty_hint"))
        }
    }

    private var studioBody: some View {
        ZStack(alignment: .top) {
            ambientHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    devicePicker
                    if studio.isDownloading {
                        loadingBlock(titleKey: "loading_artwork")
                    } else if studio.isGenerating {
                        loadingBlock(titleKey: "loading_generate")
                    } else if let error = studio.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    } else if !studio.results.isEmpty {
                        resultsGrid
                    }

                    if let exportMessage = studio.exportMessage {
                        Label(exportMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }
                .padding(24)
            }
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 560)
            #endif
        }
    }

    /// Apple Music album-page ambience: the artwork, heavily blurred and scaled up,
    /// bleeding from the top edge and dissolving into the window background.
    /// The mask both fades the image to transparent and clips the scaleEffect
    /// overflow, so the ambience ends seamlessly on any background.
    private var ambientHeader: some View {
        Group {
            if let selection {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .overlay {
                        AsyncImage(
                            url: selection.artworkURL(size: 600),
                            transaction: Transaction(animation: .easeIn(duration: 0.35))
                        ) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .transition(.opacity)
                            }
                        }
                    }
                    .clipped()
                    .blur(radius: 60)
                    .scaleEffect(1.2) // pushes the blurred feathered edges past the mask's bounds
                    .saturation(1.25)
                    .opacity(0.55)
                    .mask {
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.4),
                                .init(color: .clear, location: 1)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .allowsHitTesting(false)
                    #if os(iOS)
                    .ignoresSafeArea(edges: .top)
                    #endif
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if let selection {
                ArtworkImage(url: selection.artworkURL(size: 300))
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .cardHairline(cornerRadius: 14)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(selection.title)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(selection.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let source = studio.sourceArtwork {
                        Text("\(source.width) × \(source.height) · \(String(localized: "artwork_source_label"))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            artworkExportActions
        }
    }

    @ViewBuilder
    private var artworkExportActions: some View {
        if studio.sourceArtwork != nil || studio.isDownloading {
            HStack(spacing: 10) {
                Button {
                    #if os(macOS)
                    studio.saveArtworkViaPanel()
                    #else
                    Task { await studio.saveArtwork() }
                    #endif
                } label: {
                    Label(
                        String(localized: "save_artwork"),
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!studio.isArtworkExportReady)

                if let payload = studio.artworkSharePayload() {
                    ShareLink(
                        item: payload,
                        preview: SharePreview(
                            studio.suggestedArtworkFileName,
                            image: Image(platformImage: payload)
                        )
                    ) {
                        Label(String(localized: "share_action"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!studio.isArtworkExportReady)
                }
            }
            .font(.subheadline)
        }
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("target_device")
            } icon: {
                Image(systemName: studio.selectedDevice.symbolName)
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
            .contentTransition(.symbolEffect(.replace))
            Picker("target_device", selection: $studio.selectedDevice) {
                ForEach(DeviceProfile.allCases) { device in
                    Text("\(device.localizedTitle) · \(device.subtitle)")
                        .tag(device)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 340), spacing: 16)]
    }

    private var deviceAspect: CGFloat {
        let size = studio.selectedDevice.outputSize
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func loadingBlock(titleKey: LocalizedStringKey) -> some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonCard(aspect: deviceAspect)
                }
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(titleKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(Array(studio.results.enumerated()), id: \.element.id) { index, result in
                ResultCard(result: result, entranceIndex: index) {
                    fullScreenResult = result
                }
            }
        }
    }
}

private struct SkeletonCard: View {
    var aspect: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShimmerBox(cornerRadius: 14)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)

            ShimmerBox(cornerRadius: 5)
                .frame(width: 110, height: 14)

            ShimmerBox(cornerRadius: 5)
                .frame(height: 10)
                .padding(.trailing, 40)
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ResultCard: View {
    let result: WallpaperResult
    var entranceIndex: Int = 0
    let onPreview: () -> Void

    @State private var isHovered = false
    @State private var appeared = false

    private var previewAspectFit: CGFloat {
        let width = CGFloat(result.image.width)
        let height = CGFloat(result.image.height)
        guard width > 0, height > 0 else { return 1 }
        return width / height
    }

    /// iPhone has no pointer, so keep the badge always visible there.
    private var badgeVisible: Bool {
        #if os(iOS)
        return true
        #else
        return isHovered
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onPreview) {
                PlatformImage(cgImage: result.image)
                    .aspectRatio(previewAspectFit, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(isHovered ? 1.03 : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Label(String(localized: "preview_action"), systemImage: "eye")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(10)
                            .opacity(badgeVisible ? 1 : 0)
                    }
                    .cardHairline(cornerRadius: 14)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.24 : 0.10),
                        radius: isHovered ? 14 : 6,
                        y: isHovered ? 7 : 3
                    )
            }
            .buttonStyle(.pressFeedback)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(result.algorithm.accentColor.gradient)
                    .frame(width: 9, height: 9)
                Text(result.algorithm.title)
                    .font(.headline)
            }

            Text(result.algorithm.shortDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(Double(entranceIndex) * 0.06)) {
                appeared = true
            }
        }
    }
}
