import SwiftUI

// MARK: - Variant

enum AppVisualCardVariant {
    /// Olive-green impact background — dark text and symbol
    case brand
    /// Amber impact background — dark text and symbol
    case warm
    /// Taupe/accent impact background — muted text and symbol
    case soft
}

// MARK: - Component

struct AppVisualCard: View {
    let headline: String
    let explainer: String
    let symbol: Image
    let variant: AppVisualCardVariant
    let action: (() -> Void)?

    @Environment(\.colors) private var colors

    init(
        _ headline: String,
        explainer: String,
        symbol: Image,
        variant: AppVisualCardVariant = .brand,
        action: (() -> Void)? = nil
    ) {
        self.headline = headline
        self.explainer = explainer
        self.symbol = symbol
        self.variant = variant
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
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
                ScrollView(showsIndicators: false) {
                    textContent
                        .padding(.bottom, Spacing.n16)
                }
                .mask(scrollFadeMask)
            }
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n40)
        .frame(width: 300, height: 360, alignment: .topLeading)
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
        }
        .padding(Spacing.n24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .resolveTheme()
}
