import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct FullscreenPreview: View {
    let result: WallpaperResult
    let onClose: () -> Void
    var suggestedFileName: String = "CoverWall.jpg"

    @State private var isSaving = false
    @State private var statusMessage: LocalizedStringKey?
    @State private var errorMessage: String?
    @State private var chromeVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PreviewZoomableImage(cgImage: result.image) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    chromeVisible.toggle()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.55), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Spacer(minLength: 0)

                actionBar
                    .padding(.bottom, 16)
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)
        }
        .previewStatusBarHidden(!chromeVisible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(result.algorithm.accentColor.gradient)
                    .frame(width: 10, height: 10)
                Text(result.algorithm.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 12)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            } else if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Text(result.algorithm.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "close_action"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(String(localized: "save_photos"), systemImage: "square.and.arrow.down")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)

            if let data = jpegData {
                let payload = PlatformShareImage(data: data, name: suggestedFileName, cgImage: result.image)
                ShareLink(
                    item: payload,
                    preview: SharePreview(
                        suggestedFileName,
                        image: Image(platformImage: payload)
                    )
                ) {
                    Label(String(localized: "share_action"), systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
            }

            #if os(macOS)
            Button {
                saveViaPanel()
            } label: {
                Label(String(localized: "save_file"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            #endif
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var jpegData: Data? {
        try? PhotoExportService.jpegData(from: result.image)
    }

    private func save() async {
        isSaving = true
        statusMessage = nil
        errorMessage = nil
        do {
            try await PhotoExportService.saveToPhotoLibrary(result.image)
            statusMessage = "export_saved_photos"
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    #if os(macOS)
    private func saveViaPanel() {
        do {
            try PhotoExportService.savePanelWrite(result.image, suggestedName: suggestedFileName)
            statusMessage = "export_saved_file"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif
}

// MARK: - Zoomable fit image

/// Always aspect-fits the full image in the available space (no scrolling).
/// Pinch / trackpad / scroll-wheel zooms; pan while zoomed; tap toggles the chrome when at fit scale.
private struct PreviewZoomableImage: View {
    let cgImage: CGImage
    let onTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var container: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 8

    private var isZoomed: Bool { scale > 1.02 }

    var body: some View {
        GeometryReader { proxy in
            PlatformImage(cgImage: cgImage)
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            applyScale(lastScale * value)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if !isZoomed {
                                resetZoom()
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard isZoomed else { return }
                            let proposed = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                            offset = clampedOffset(proposed)
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                #if os(macOS)
                .overlay {
                    ScrollWheelZoomCatcher { deltaY in
                        zoomWithScrollWheel(deltaY: deltaY)
                    }
                    .allowsHitTesting(true)
                }
                #endif
                .onTapGesture {
                    if isZoomed {
                        resetZoom()
                    } else {
                        onTap()
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(String(localized: "toggle_chrome_action"))
                .onAppear {
                    container = proxy.size
                }
                .onChange(of: proxy.size) { _, newSize in
                    container = newSize
                    offset = clampedOffset(offset)
                    lastOffset = offset
                }
        }
        .clipped()
    }

    private func applyScale(_ raw: CGFloat) {
        let next = clampScale(raw)
        scale = next
        offset = clampedOffset(offset)
    }

    #if os(macOS)
    private func zoomWithScrollWheel(deltaY: CGFloat) {
        guard deltaY != 0 else { return }
        let factor = deltaY > 0 ? CGFloat(1.06) : CGFloat(1 / 1.06)
        applyScale(scale * factor)
        lastScale = scale
        lastOffset = offset
        if !isZoomed {
            resetZoom()
        }
    }
    #endif

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(maxScale, max(minScale, value))
    }

    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, cgImage.height > 0 else { return proposed }

        let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let fitted: CGSize
        if container.width / container.height > imageAspect {
            fitted = CGSize(width: container.height * imageAspect, height: container.height)
        } else {
            fitted = CGSize(width: container.width, height: container.width / imageAspect)
        }

        let scaledWidth = fitted.width * scale
        let scaledHeight = fitted.height * scale
        let maxX = max(0, (scaledWidth - container.width) / 2)
        let maxY = max(0, (scaledHeight - container.height) / 2)

        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }
}

#if os(macOS)
/// Transparent NSView that forwards scroll-wheel deltas for image zoom.
/// SwiftUI's `onScrollWheel` is unavailable in this project's SDK surface.
private struct ScrollWheelZoomCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only intercept scroll-wheel so taps/drags pass through to SwiftUI.
        if NSApp.currentEvent?.type == .scrollWheel {
            return self
        }
        return nil
    }
}
#endif

// MARK: - Platform helpers

private extension View {
    /// Hides the status bar in immersive preview mode (iOS only).
    func previewStatusBarHidden(_ hidden: Bool) -> some View {
        #if os(iOS)
        self.statusBarHidden(hidden)
        #else
        self
        #endif
    }
}

// MARK: - Share payload

struct PlatformShareImage: Transferable {
    let data: Data
    let name: String
    let cgImage: CGImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { payload in
            payload.data
        }
        .suggestedFileName { payload in
            payload.name
        }
    }
}

extension Image {
    init(platformImage: PlatformShareImage) {
        #if canImport(UIKit)
        self.init(uiImage: UIImage(cgImage: platformImage.cgImage))
        #elseif canImport(AppKit)
        self.init(nsImage: NSImage(cgImage: platformImage.cgImage, size: .zero))
        #else
        self.init(systemName: "photo")
        #endif
    }
}
