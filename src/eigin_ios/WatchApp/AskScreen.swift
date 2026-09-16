import SwiftUI

/// The watch companion: the blob and one line under it, pushed anywhere to
/// talk and released to send. Ready, listening, sending are everything the
/// wrist ever shows — the reply itself arrives as a notification from the
/// phone.
struct AskScreen: View {
    @Environment(\.colors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AskModel

    init(model: AskModel) {
        self.model = model
    }

    /// The one-line prompt under the blob.
    private var prompt: String {
        if let error = model.error { return error }
        return switch model.phase {
        case .ready: Localized.Watch.pushToTalk
        case .listening: Localized.Watch.releaseToSend
        case .sending: Localized.Watch.sending
        }
    }

    /// The pulse: swell fraction and cycle length.
    private static let pulseAmplitude = 0.06
    private static let pulsePeriod: TimeInterval = 3.0

    var body: some View {
        VStack(spacing: Spacing.n12) {
            ZStack {
                if model.phase == .sending {
                    // While the question is in flight the blob is gone; the
                    // slot stays reserved, so the prompt never jumps.
                    Color.clear.frame(width: 88, height: 88)
                } else {
                    blob
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 88, height: 88)

            Text(prompt)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .padding(.horizontal, Spacing.n12)
                .opacity(model.phase == .sending ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Animations.gentle, value: model.phase)
        // Push-to-talk lives on the press itself, so the whole screen is the
        // button and the release cannot be mistaken for another tap.
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, perform: {}) { pressing in
            if pressing {
                model.pressBegan()
            } else {
                model.pressEnded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.handleDismissal()
            }
        }
    }

    private var blob: some View {
        MorphBlob(
            shownAt: model.shownAt,
            intensity: .none,
            breath: model.pulse,
            breathPulse: Self.pulseAmplitude,
            breathPeriod: Self.pulsePeriod,
            color: colors.button.spot.base
        )
    }
}
