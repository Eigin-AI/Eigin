import SwiftUI

/// Chat-specific navigation header: back to list, agent avatar, and phone /
/// live-call button.
struct ChatHeaderView: View {
    let chat: Chat?
    let emoji: String?
    let onBack: () -> Void
    let onPhone: () -> Void
    let isPhoneDisabled: Bool

    init(
        chat: Chat?,
        emoji: String? = nil,
        onBack: @escaping () -> Void,
        onPhone: @escaping () -> Void,
        isPhoneDisabled: Bool = false
    ) {
        self.chat = chat
        self.emoji = emoji
        self.onBack = onBack
        self.onPhone = onPhone
        self.isPhoneDisabled = isPhoneDisabled
    }

    var body: some View {
        AppNavigationHeader(
            leading: {
                AppActionButton(
                    icon: Iconography.Functional.note,
                    variant: .open,
                    size: .medium,
                    action: onBack
                )
            },
            center: {
                AppBrandAvatar(emoji: emoji)
            },
            trailing: {
                AppActionButton(
                    icon: Iconography.Functional.phone,
                    variant: .open,
                    size: .medium,
                    action: onPhone
                )
                .disabled(isPhoneDisabled)
            }
        )
    }
}
