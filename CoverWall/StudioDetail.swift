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

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if let selection {
                AsyncImage(url: URL(string: selection.artworkUrl100)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12))

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
        }
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("target_device")
                .font(.headline)
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

    private func loadingBlock(titleKey: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(titleKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var resultsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 340), spacing: 16)],
            spacing: 16
        ) {
            ForEach(studio.results) { result in
                ResultCard(result: result) {
                    fullScreenResult = result
                }
            }
        }
    }
}

struct ResultCard: View {
    let result: WallpaperResult
    let onPreview: () -> Void

    private var previewAspectFit: CGFloat {
        let width = CGFloat(result.image.width)
        let height = CGFloat(result.image.height)
        guard width > 0, height > 0 else { return 1 }
        return width / height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onPreview) {
                PlatformImage(cgImage: result.image)
                    .aspectRatio(previewAspectFit, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Label(String(localized: "preview_action"), systemImage: "eye")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(10)
                    }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Circle()
                    .fill(result.algorithm.accentColor)
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
    }
}
