import SwiftUI

/// Button-only content for a tool-permission prompt.
///
/// Present with ``.appSheet`` and pass the description through the modifier's
/// `description:` parameter so it renders in ``AppSheetHeader``.
struct PermissionRequestSheetContent: View {
    let allowOnceLabel: String
    let allowForChatLabel: String
    let denyLabel: String
    let onResponse: (PermissionResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didRespond = false

    var body: some View {
        VStack(spacing: contentGap) {
            AppButton(allowOnceLabel, variant: .primary) {
                respond(.allowOnce)
            }
            .padding(.horizontal, contentPx)

            AppButton(allowForChatLabel, variant: .spot) {
                respond(.allowForChat)
            }
            .padding(.horizontal, contentPx)

            AppButton(denyLabel, variant: .destructive) {
                respond(.deny)
            }
            .padding(.horizontal, contentPx)
        }
        .onDisappear {
            if !didRespond {
                onResponse(.deny)
            }
        }
    }

    private func respond(_ response: PermissionResponse) {
        didRespond = true
        onResponse(response)
        dismiss()
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

// MARK: - Preview

#Preview("Permission Request Sheet") {
    PermissionRequestSheetPreview()
        .resolveTheme()
}

private struct PermissionRequestSheetPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()

            VStack {
                Spacer()
                PermissionRequestSheetContent(
                    allowOnceLabel: "Allow Once",
                    allowForChatLabel: "Allow for Chat",
                    denyLabel: "Deny"
                ) { _ in }
            }
        }
    }
}
