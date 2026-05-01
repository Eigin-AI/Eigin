import SwiftUI

/// A circular progress indicator that fills a ring based on completion fraction.
struct CircularProgressView: View {
    let progress: Double
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2.5
    var accentColor: Color?

    @Environment(\.colors) private var colors

    private var foreground: Color {
        accentColor ?? colors.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(colors.textSecondary.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(foreground, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
        }
        .frame(width: size, height: size)
    }
}
