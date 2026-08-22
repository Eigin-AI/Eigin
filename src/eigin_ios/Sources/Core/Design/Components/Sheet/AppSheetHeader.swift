import SwiftUI

struct AppSheetHeader: View {
    var label: String?
    let title: String
    var description: String?
    /// Rich, dynamic description in place of the plain `description` string.
    /// Rendered in the header group so it inherits description spacing/inset.
    var descriptionContent: AnyView?
    var onDismiss: (() -> Void)?

    @Environment(\.colors) private var colors
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var px: CGFloat {
        sizeClass == .regular
            ? Sizing.PageLayout.HeaderGrouping.Px.tablet
            : Sizing.PageLayout.HeaderGrouping.Px.mobile
    }

    var body: some View {
        HStack(alignment: label != nil || description != nil || descriptionContent != nil ? .top :
            .center)
        {
            VStack(alignment: .leading, spacing: Sizing.PageLayout.HeaderGrouping.gap) {
                if let label {
                    Text(label)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
                VStack(alignment: .leading, spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    Text(title)
                        .typography(Typography.titleS)
                        .foregroundStyle(colors.text.standard.base)
                    if let descriptionContent {
                        descriptionContent
                    } else if let description {
                        Text(description)
                            .typography(Typography.description)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                AppActionButton(
                    icon: Image(systemName: "xmark"),
                    variant: .open,
                    size: .medium,
                    action: onDismiss
                )
            }
        }
        .padding(.horizontal, px)
    }
}

// MARK: - Preview

#Preview("Variants") {
    AppSheetHeaderPreview()
        .resolveTheme()
}

private struct AppSheetHeaderPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.n24) {
                AppSheetHeader(title: "Headline goes here", onDismiss: {})

                AppSheetHeader(
                    label: "Step 1 of 3",
                    title: "Choose a time",
                    onDismiss: {}
                )

                AppSheetHeader(
                    title: "Pick a date",
                    description: "Select the date you would like to use for this entry.",
                    onDismiss: {}
                )

                AppSheetHeader(
                    label: "Step 2 of 3",
                    title: "Confirm details",
                    description: "Review the information below before continuing.",
                    onDismiss: {}
                )

                AppSheetHeader(title: "No close button")
            }
            .padding(.vertical, Spacing.n24)
        }
        .background(colors.surface.standard.base)
    }
}
