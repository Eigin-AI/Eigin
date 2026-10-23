import SwiftUI

/// Waiting, with nothing to count: a track and a short arc drifting round it.
/// Running, without guessing how far along. Mirrors `SweepRing.svelte`.
struct SweepRing: View {
    /// Outer diameter. Callers pass it; the default is the design's standard
    /// ring size.
    var size: CGFloat = Sizing.Button.Icon.large
    /// Track and arc width, inset within the outer diameter.
    var stroke: CGFloat = 4

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sweeping = false

    private let arc = 0.18
    private let period: Double = 1.6

    var body: some View {
        Circle()
            .stroke(colors.border.standard.base, lineWidth: stroke)
            .overlay {
                Circle()
                    .trim(from: 0, to: arc)
                    .stroke(colors.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            .frame(width: size - stroke, height: size - stroke)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(sweeping ? 360 : 0))
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                    sweeping = true
                }
            }
    }
}

#Preview {
    SweepRing(size: 40)
        .padding()
        .background(Color.black)
        .resolveTheme()
}
