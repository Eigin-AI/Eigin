import SwiftUI

#Preview("Activity transitions") {
    ThinkingIndicatorActivityPreview()
        .resolveTheme()
}

private struct ThinkingIndicatorActivityPreview: View {
    @Environment(\.colors) private var colors
    @State private var indicator = ThinkingIndicatorState()
    @State private var isStalled = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n24) {
            if let shownAt = indicator.shownAt {
                ThinkingIndicator(
                    shownAt: shownAt,
                    clockStart: indicator.clockStart,
                    priorElapsed: indicator.priorElapsed,
                    activity: indicator.activity,
                    isStalled: isStalled
                )
            }
            Button("Finish tools → thinking") {
                setActivity(.thinking)
            }
            Button("Start tools → working") {
                setActivity(.working)
            }
            Toggle("Waiting for user", isOn: Binding(
                get: { isStalled },
                set: {
                    isStalled = $0
                    indicator.setStalled($0)
                }
            ))
        }
        .padding(Spacing.n32)
        .background(colors.surface.standard.base)
        .onAppear {
            indicator.setActivity(.working)
            indicator.setShown(true)
        }
        .onDisappear {
            indicator.setShown(false)
        }
    }

    private func setActivity(_ activity: ThinkingActivity) {
        if isStalled {
            isStalled = false
            indicator.setStalled(false)
        }
        indicator.setActivity(activity)
    }
}
