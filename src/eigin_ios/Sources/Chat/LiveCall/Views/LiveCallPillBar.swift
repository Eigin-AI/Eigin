import SwiftUI

/// Pill-shaped bottom bar for live call controls.
///
/// Mirrors the inactive chat input bar — rounded pill surface, elevated
/// background, holding icon-only action buttons.
struct LiveCallPillBar: View {
    let service: LiveCallService
    let onEnd: () -> Void

    @Environment(\.colors) private var colors

    var body: some View {
        LiveCallControls(service: service, onEnd: onEnd)
            .padding(.vertical, Spacing.n8)
            .padding(.horizontal, Spacing.n8)
            .frame(minHeight: Sizing.Button.Action.medium)
            .background(
                colors.surface.standard.elevated,
                in: RoundedRectangle(cornerRadius: Radius.full, style: .continuous)
            )
            .padding(.horizontal, Spacing.n8)
            .frame(maxWidth: .infinity)
    }
}
