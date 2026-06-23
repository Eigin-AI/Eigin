import SwiftUI

/// The three call-control buttons rendered as icon-only action buttons.
///
/// Permission prompts are handled separately by the shared
/// ``PermissionRequestSheetContent`` sheet, where the labelled buttons carry
/// enough context that icons aren't needed.
struct LiveCallControls: View {
    let service: LiveCallService
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: Spacing.n16) {
            speedButton
            Spacer()
            hangUpButton
            Spacer()
            interruptButton
        }
        .frame(maxWidth: .infinity)
    }

    private var speedButton: some View {
        speedActionButton
            .overlay {
                Menu {
                    ForEach(LiveCallService.ResponseSpeed.allCases, id: \.self) { speed in
                        Button {
                            Haptics.light()
                            service.responseSpeed = speed
                        } label: {
                            Label(speed.label, systemImage: speed.iconName)
                        }
                    }
                } label: {
                    Color.clear
                }
            }
    }

    private var speedActionButton: some View {
        AppActionButton(
            icon: Image(systemName: service.responseSpeed.iconName),
            variant: .primary,
            size: .medium,
            action: {}
        )
        .contentTransition(.symbolEffect(.replace))
    }

    private var hangUpButton: some View {
        AppActionButton(
            icon: Image(systemName: "phone.down.fill"),
            variant: .destructive,
            size: .medium,
            action: {
                Haptics.medium()
                onEnd()
            }
        )
    }

    private var interruptButton: some View {
        AppActionButton(
            icon: Image(systemName: "hand.raised.fill"),
            variant: .primary,
            size: .medium,
            action: {
                Haptics.medium()
                service.interrupt()
            }
        )
        .disabled(service.phase == .idle || service.phase == .listening)
    }
}
