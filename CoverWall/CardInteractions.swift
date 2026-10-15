import SwiftUI

/// Shared interaction & visual polish primitives used by the search grid,
/// studio result cards, and loading placeholders.

// MARK: - Press feedback

/// Scales the label down slightly while pressed and springs back on release.
/// Visually equivalent to `.plain`, so callers keep full control of layout.
struct PressFeedbackButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressFeedbackButtonStyle {
    static var pressFeedback: PressFeedbackButtonStyle { PressFeedbackButtonStyle() }
}

// MARK: - Artwork image

/// Async artwork image with a quiet placeholder and a fade-in once loaded.
/// Callers own sizing and clipping (placeholder intentionally has no corners).
struct ArtworkImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: phase.error != nil ? "exclamationmark.triangle" : "music.note")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
    }
}

// MARK: - Shimmer placeholder

/// Rounded box with a slow light sweep, used to build skeleton loading cards.
struct ShimmerBox: View {
    var cornerRadius: CGFloat = 8

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [.clear, .primary.opacity(0.10), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(width * 0.5, 40))
                    .offset(x: phase * width * 1.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Card chrome

extension View {
    /// Hairline border that keeps artwork edges crisp on light backgrounds.
    func cardHairline(cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
