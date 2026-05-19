import SwiftUI

/// Chat-specific navigation header: back to list, brand avatar, and phone / live-call button.
struct ChatHeaderView: View {
    let chat: Chat?
    let onBack: () -> Void
    let onPhone: () -> Void
    let isPhoneDisabled: Bool

    init(
        chat: Chat?,
        onBack: @escaping () -> Void,
        onPhone: @escaping () -> Void,
        isPhoneDisabled: Bool = false
    ) {
        self.chat = chat
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
                AppBrandAvatar(image: Iconography.Brand.avatar, action: {})
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
