import SwiftUI

/// Controls whether ``AppDisclosure`` draws its own card surface.
///
/// - `.card`: the default — renders a rounded, filled background.
///   Use when the disclosure stands alone.
/// - `.open`: no background or clip. Use when embedding inside an
///   ``AppCardSurface`` alongside other rows separated by dividers.
enum AppDisclosureVariant {
    case card
    case open
}

/// A fold-out: a titled row that hides configurable content until tapped,
/// then grows to reveal it. The title names the disclosure and an optional
/// description summarises the current choice (for example the picked option).
/// Content is a `@ViewBuilder` slot, so a disclosure makes no assumptions
/// about what it holds.
///
/// Expansion is self-managed; seed the opening state with `initiallyExpanded`.
///
/// Pass `variant: .open` to embed the disclosure inside an ``AppCardSurface``
/// without double-wrapping backgrounds.
struct AppDisclosure<Content: View>: View {
    let title: String
    let description: String?
    let variant: AppDisclosureVariant
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool
    @Environment(\.colors) private var colors

    init(
        _ title: String,
        description: String? = nil,
        variant: AppDisclosureVariant = .card,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.description = description
        self.variant = variant
        self.content = content
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                contentDivider
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.n24)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(variant == .card ? colors.surface.standard.alternative : .clear)
        .clipShape(RoundedRectangle(cornerRadius: variant == .card ? Radius.card : 0))
    }

    // MARK: - Header

    /// The always-visible, tappable row. It is the only toggle target so taps
    /// inside the revealed content never collapse the disclosure.
    private var header: some View {
        HStack(spacing: Spacing.n16) {
            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(title)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)

                if let description {
                    Text(description)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }

            Spacer()

            PlusMinusIndicator(isExpanded: isExpanded)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Animations.smooth) { isExpanded.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    // MARK: - Divider

    /// Hairline separating the header from the revealed content, inset to line
    /// up with the title and content padding.
    private var contentDivider: some View {
        Rectangle()
            .fill(colors.input.standard.inactive)
            .frame(height: 1)
            .padding(.horizontal, Spacing.n24)
    }
}

// MARK: - Preview

private struct AppDisclosurePreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.n16) {
                AppDisclosure("AI model", description: "Llama 3 · lokal") {
                    placeholderContent
                }

                AppDisclosure("Privatliv") {
                    placeholderContent
                }

                AppDisclosure(
                    "Sprog & region",
                    description: "Dansk",
                    initiallyExpanded: true
                ) {
                    placeholderContent
                }

                AppDisclosure(
                    "Sikkerhedskopi",
                    description: "Senest i går",
                    initiallyExpanded: true
                ) {
                    buttonContent
                }

                // Embedded variant
                AppCardSurface(padding: 0) {
                    VStack(spacing: 0) {
                        AppDisclosure("Embedded row 1", variant: .open) {
                            placeholderContent
                        }
                        Divider().padding(.horizontal, Spacing.n24)
                        AppDisclosure("Embedded row 2", variant: .open) {
                            placeholderContent
                        }
                    }
                }
            }
            .padding(Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }

    private var placeholderContent: some View {
        VStack(alignment: .leading, spacing: Spacing.n12) {
            Text(verbatim: "Any content folds out here.")
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
            Text(verbatim: "Buttons, lists, options — the disclosure stays agnostic.")
                .typography(Typography.descriptionSmall)
                .foregroundStyle(colors.text.standard.muted)
        }
    }

    private var buttonContent: some View {
        VStack(spacing: Spacing.n12) {
            AppButton("Sikkerhedskopiér nu") {}
            AppButton("Planlæg", variant: .secondary) {}
        }
    }
}

#Preview("Light") {
    AppDisclosurePreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppDisclosurePreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
