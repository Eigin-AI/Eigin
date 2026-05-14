import SwiftUI

/// The three call-control buttons: Turn Delay, End, My Turn.
/// Morphs into permission prompt buttons when a tool requires user approval.
struct LiveCallControls: View {
    let service: LiveCallService
    let onEnd: () -> Void

    @Environment(\.colors) private var colors

    private var isPrompting: Bool {
        service.chatLoop.pendingPermission != nil
    }

    /// Tracks the visible button set with a delay to prevent accidental taps.
    @State private var showButtons = true

    var body: some View {
        HStack {
            if showButtons {
                if isPrompting {
                    permissionButtons
                        .transition(.blurReplace)
                } else {
                    callButtons
                        .transition(.blurReplace)
                }
            }
        }
        .frame(minHeight: 66)
        .animation(Animations.snap, value: isPrompting)
        .animation(Animations.snap, value: showButtons)
        .onChange(of: isPrompting) {
            if isPrompting {
                service.playPermissionSound()
            }
            showButtons = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showButtons = true
            }
        }
    }

    // MARK: - Call Controls

    private var callButtons: some View {
        HStack {
            callButton(
                icon: service.responseSpeed.iconName,
                label: Localized.Settings.turnDelay,
                background: colors.text.standard.muted.opacity(0.1)
            ) {
                // Handled by menu
            }
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
            .contentTransition(.symbolEffect(.replace))

            callButton(
                icon: "phone.down.fill",
                label: Localized.Ui.end,
                background: Color(hex: "#FF0004"),
                iconColor: .white
            ) {
                Haptics.medium()
                onEnd()
            }

            callButton(
                icon: "hand.raised.fill",
                label: Localized.Chat.myTurn,
                background: colors.text.standard.muted.opacity(0.1)
            ) {
                service.interrupt()
            }
            .disabled(service.phase == .idle || service.phase == .listening)
            .opacity(service.phase == .idle || service.phase == .listening ? 0.4 : 1)
        }
    }

    // MARK: - Permission Controls

    private var permissionButtons: some View {
        HStack {
            callButton(
                icon: "xmark",
                label: Localized.Permission.deny,
                background: colors.text.standard.muted.opacity(0.1)
            ) {
                Haptics.light()
                service.chatLoop.resolvePermission(.deny)
            }

            callButton(
                icon: "checkmark",
                label: Localized.Permission.allowOnce,
                background: colors.accent,
                iconColor: .white
            ) {
                Haptics.light()
                service.chatLoop.resolvePermission(.allowOnce)
            }

            callButton(
                icon: "checkmark.circle",
                label: Localized.Permission.allowForChat,
                background: colors.text.standard.muted.opacity(0.1)
            ) {
                Haptics.light()
                service.chatLoop.resolvePermission(.allowForChat)
            }
        }
    }

    // MARK: - Shared Button

    private func callButton(
        icon: String,
        label: String,
        background: some ShapeStyle,
        iconColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.n4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor ?? colors.text.standard.muted)
                    .frame(width: 44, height: 44)
                    .background(background)
                    .clipShape(Circle())

                Text(label)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
