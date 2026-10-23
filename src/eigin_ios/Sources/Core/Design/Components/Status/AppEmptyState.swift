import SwiftUI

/// An absence of content, with context and an optional recovery action.
struct AppEmptyState<Action: View>: View {
    let icon: Image
    let title: String
    let description: String?
    @ViewBuilder let action: () -> Action

    @Environment(\.colors) private var colors

    init(icon: Image, title: String, description: String? = nil) where Action == EmptyView {
        self.icon = icon
        self.title = title
        self.description = description
        action = { EmptyView() }
    }

    init(
        icon: Image,
        title: String,
        description: String? = nil,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.n16) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: Spacing.n48, height: Spacing.n48)
                .foregroundStyle(colors.icon.standard.muted)
                .accessibilityHidden(true)
            Text(title)
                .typography(Typography.titleS)
                .foregroundStyle(colors.text.standard.base)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
                    .frame(maxWidth: 320)
            }
            action()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
