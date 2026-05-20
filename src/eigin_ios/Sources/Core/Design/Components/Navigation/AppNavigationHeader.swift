import SwiftUI

/// A custom top navigation header with three configurable slots.
///
/// Displays leading, center, and trailing views separated by spacers.
/// The center slot is bottom-aligned; leading and trailing slots are
/// vertically centered within the fixed `Spacing.n64` height.
///
/// Only the `leading` slot is required. `center` and `trailing` default to
/// `EmptyView` and can be omitted for simple back-nav headers.
struct AppNavigationHeader<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let center: () -> Center
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.colors) private var colors

    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder center: @escaping () -> Center = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading
        self.center = center
        self.trailing = trailing
    }

    var body: some View {
        contentFrame
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.n56)
            .padding(.bottom, Spacing.n16)
            .padding(.horizontal, Spacing.n16)
            .background(colors.surface.standard.base)
    }

    private var contentFrame: some View {
        ZStack(alignment: .bottom) {
            center()
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 0) {
                leading()
                Spacer()
                trailing()
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: Spacing.n64)
    }
}

// MARK: - Preview

#Preview("Full Light") {
    HeaderFullPreview()
        .resolveTheme()
}

#Preview("Full Dark") {
    HeaderFullPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

#Preview("Leading Only Light") {
    HeaderLeadingPreview()
        .resolveTheme()
}

#Preview("Leading Only Dark") {
    HeaderLeadingPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

private struct HeaderFullPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.note,
                        variant: .open,
                        size: .medium,
                        action: {}
                    )
                },
                center: {
                    AppBrandAvatar(
                        image: Iconography.Brand.avatar,
                        action: {}
                    )
                },
                trailing: {
                    AppActionButton(
                        icon: Iconography.Functional.plus,
                        variant: .open,
                        size: .medium,
                        action: {}
                    )
                }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.n16) {
                    Text(
                        "You have a hard time making it to your appointment with Thomas in Brønshøj at 5pm. Your workshop at the office ends at 4:30pm, and the trip takes about 35 minutes."
                    )
                    .typography(Typography.chatMessage)
                    .foregroundStyle(colors.text.standard.base)

                    HStack {
                        Spacer()
                        Text("What do you suggest?")
                            .typography(Typography.chatMessageUser)
                            .foregroundStyle(colors.text.standard.base)
                            .padding(Spacing.n16)
                            .background(colors.surface.standard.alternative)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    }

                    Text(
                        "I can move the appointment, send Thomas a message, or find a faster route. What works best?"
                    )
                    .typography(Typography.chatMessage)
                    .foregroundStyle(colors.text.standard.base)
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n24)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(colors.surface.standard.base)
    }
}

private struct HeaderLeadingPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader {
                AppActionButton(
                    icon: Iconography.Functional.Arrow.left,
                    variant: .open,
                    size: .medium,
                    action: {}
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.n16) {
                    Text("Conversation content goes here")
                        .typography(Typography.body)
                        .foregroundStyle(colors.text.standard.base)
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n24)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(colors.surface.standard.base)
    }
}
