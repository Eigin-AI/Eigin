import SwiftUI

// MARK: - Variant

enum AppVisualCardVariant {
    /// Olive-green impact background — dark text and symbol
    case brand
    /// Amber impact background — dark text and symbol
    case warm
    /// Taupe/accent impact background — muted text and symbol
    case soft
    /// Neutral elevated background — muted text and symbol
    case neutral
}

// MARK: - Component

struct AppVisualCard: View {
    let headline: String
    let explainer: String
    let symbol: Image
    let variant: AppVisualCardVariant
    /// Design size. Under a shorter container (iPhone SE, iPad compatibility
    /// mode) the card goes compact: smaller symbol, title only, tightened text.
    var width: CGFloat = 300
    var height: CGFloat = 360
    let action: (() -> Void)?

    @Environment(\.colors) private var colors

    init(
        _ headline: String,
        explainer: String,
        symbol: Image,
        variant: AppVisualCardVariant = .brand,
        width: CGFloat = 300,
        height: CGFloat = 360,
        action: (() -> Void)? = nil
    ) {
        self.headline = headline
        self.explainer = explainer
        self.symbol = symbol
        self.variant = variant
        self.width = width
        self.height = height
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { current }
                .buttonStyle(.plain)
        } else {
            current
        }
    }

    @ViewBuilder
    private var current: some View {
        if isCompact { compactCard } else { card }
    }

    private var isCompact: Bool {
        height < 360
    }

    /// Squeezed card: the symbol scales down with the height, and the title
    /// and explainer tuck underneath at smaller styles. ViewThatFits drops
    /// the explainer only if nothing else fits.
    private var compactCard: some View {
        let symbolSize = height * 0.26

        return VStack(alignment: .leading, spacing: 0) {
            symbol
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: symbolSize, height: symbolSize)
                .foregroundStyle(foregroundColor)

            Spacer(minLength: Spacing.n12)

            ViewThatFits(in: .vertical) {
                compactText
                Text(headline)
                    .typography(Typography.titleXS)
                    .foregroundStyle(foregroundColor)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n24)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    private var compactText: some View {
        VStack(alignment: .leading, spacing: Spacing.n8) {
            Text(headline)
                .typography(Typography.titleXS)
                .foregroundStyle(foregroundColor)
            Text(explainer)
                .typography(Typography.description)
                .foregroundStyle(foregroundColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            symbol
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 110, height: 110)
                .foregroundStyle(foregroundColor)

            Spacer(minLength: Spacing.n24)

            ViewThatFits(in: .vertical) {
                textContent
                headlineOnly
                ScrollView(showsIndicators: false) {
                    textContent
                        .padding(.bottom, Spacing.n16)
                }
                .mask(scrollFadeMask)
            }
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n40)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: Sizing.Card.Gap.text - 8) {
            Text(headline)
                .typography(Typography.titleL)
                .foregroundStyle(foregroundColor)
                .lineLimit(nil)
            Text(explainer)
                .typography(Typography.description)
                .foregroundStyle(foregroundColor)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headlineOnly: some View {
        Text(headline)
            .typography(Typography.titleL)
            .foregroundStyle(foregroundColor)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrollFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var backgroundColor: Color {
        switch variant {
        case .brand: colors.surface.impact.base
        case .warm: colors.surface.impact.alternative
        case .soft: colors.surface.impact.subtle
        case .neutral: colors.surface.standard.elevated
        }
    }

    private var foregroundColor: Color {
        colors.text.button.onPrimary
    }
}

// MARK: - Previews

#Preview("Visual Cards") {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.n16) {
            AppVisualCard(
                "Morning focus",
                explainer: "One clear priority.",
                symbol: Iconography.Brand.avatar,
                variant: .brand
            )
            AppVisualCard(
                "Here's the good news",
                explainer: "A quick summary of what changed while you were away, including a few items that may need your attention soon.",
                symbol: Iconography.Brand.security,
                variant: .warm,
                action: { print("Tapped: warm card") }
            )
            AppVisualCard(
                "Your week at a glance",
                explainer: "Four meetings, two deadlines, and one thing you said you'd get to eventually.",
                symbol: Iconography.Brand.chatFill,
                variant: .soft
            )
            AppVisualCard(
                "Something else",
                explainer: "Write your own answer",
                symbol: Iconography.Functional.edit,
                variant: .neutral,
                action: { print("Tapped: neutral card") }
            )
        }
        .padding(Spacing.n24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .resolveTheme()
}
