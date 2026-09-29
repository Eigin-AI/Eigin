import SwiftUI

/// A custom top navigation header with three configurable slots.
///
/// Displays leading, center, and trailing views separated by spacers.
/// Leading and trailing slots are vertically centered within the fixed
/// `Spacing.n64` height. The center slot defaults to bottom alignment so the
/// brand avatar sits grounded against the action buttons; pass a `title:`
/// instead to render a vertically-centered text title.
///
/// Owns its own safe-area handling: the surface background extends into the
/// top safe area so the app background never shows behind the status bar,
/// and `.safeAreaPadding(.top, Spacing.n4)` ensures a small minimum gap
/// when the system inset is absent (e.g. landscape).
///
/// Place it as the top element of a `VStack(spacing: 0)` above the scrollable
/// content; the header's own background bleeds into the top safe area, so the
/// owner only needs an opaque content background below it. Only the `leading`
/// slot is required. `center` and `trailing` default to `EmptyView` and can be
/// omitted for simple back-nav headers.
struct AppNavigationHeader<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let center: () -> Center
    @ViewBuilder let trailing: () -> Trailing
    let centerAlignment: VerticalAlignment

    @Environment(\.colors) private var colors

    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder center: @escaping () -> Center = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading
        self.center = center
        self.trailing = trailing
        centerAlignment = .bottom
    }

    /// Convenience header with a vertically-centered text title in the center
    /// slot, styled consistently. Use for simple titled screens that don't show
    /// the brand avatar.
    init(
        title: String,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) where Center == HeaderTitle {
        self.leading = leading
        center = { HeaderTitle(title: title) }
        self.trailing = trailing
        centerAlignment = .center
    }

    var body: some View {
        contentFrame
            .frame(maxWidth: .infinity)
            .padding(.bottom, Spacing.n16)
            .padding(.horizontal, Spacing.n16)
            .background(colors.surface.standard.base.ignoresSafeArea(edges: .top))
            .safeAreaPadding(.top, Spacing.n4)
    }

    private var contentFrame: some View {
        ZStack {
            center()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: Alignment(horizontal: .center, vertical: centerAlignment)
                )

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

/// The standardized title rendered by `AppNavigationHeader(title:)`. Horizontal
/// padding reserves room for the edge action buttons so a long title truncates
/// rather than sliding underneath them.
struct HeaderTitle: View {
    let title: String

    @Environment(\.colors) private var colors

    var body: some View {
        Text(title)
            .typography(Typography.titleXS)
            .foregroundStyle(colors.text.standard.base)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Spacing.n64)
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

#Preview("Titled Light") {
    HeaderTitledPreview()
        .resolveTheme()
}

#Preview("Titled Dark") {
    HeaderTitledPreview()
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
                    AppBrandAvatar(action: {})
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
                        verbatim: "You have a hard time making it to your appointment with Thomas in Brønshøj at 5pm. Your workshop at the office ends at 4:30pm, and the trip takes about 35 minutes."
                    )
                    .typography(Typography.chatMessage)
                    .foregroundStyle(colors.text.standard.base)

                    HStack {
                        Spacer()
                        Text(verbatim: "What do you suggest?")
                            .typography(Typography.chatMessageUser)
                            .foregroundStyle(colors.text.standard.base)
                            .padding(Spacing.n16)
                            .background(colors.surface.standard.alternative)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    }

                    Text(
                        verbatim: "I can move the appointment, send Thomas a message, or find a faster route. What works best?"
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
                    Text(verbatim: "Conversation content goes here")
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

private struct HeaderTitledPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: "Spaces",
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
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

            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(colors.surface.standard.base)
    }
}
