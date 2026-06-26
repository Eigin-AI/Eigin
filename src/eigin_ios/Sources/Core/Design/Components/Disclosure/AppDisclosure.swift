import SwiftUI

/// A fold-out card: a titled surface that hides configurable content until
/// tapped, then grows to reveal it. The title names the disclosure and an
/// optional description summarises the current choice (for example the picked
/// option). Content is a `@ViewBuilder` slot, so a disclosure makes no
/// assumptions about what it holds.
///
/// Expansion is self-managed; seed the opening state with `initiallyExpanded`.
struct AppDisclosure<Content: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool
    @Environment(\.colors) private var colors

    init(
        _ title: String,
        description: String? = nil,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                divider
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.n24)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.standard.alternative)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: - Header

    /// The always-visible, tappable row. It is the only toggle target so taps
    /// inside the revealed content never collapse the card.
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
        .padding(Spacing.n24)
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
    private var divider: some View {
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
            }
            .padding(Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }

    private var placeholderContent: some View {
        VStack(alignment: .leading, spacing: Spacing.n12) {
            Text("Any content folds out here.")
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
            Text("Buttons, lists, options — the disclosure stays agnostic.")
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
