import SwiftUI

struct AppCard: View {
    let size: AppCardSize
    let headline: String
    let explainer: String
    let image: Image?
    let height: CGFloat
    let action: (() -> Void)?

    @Environment(\.colors) private var colors

    /// Compact card — no image
    init(_ headline: String, explainer: String, action: (() -> Void)? = nil) {
        size = .compact
        self.headline = headline
        self.explainer = explainer
        height = 0
        image = nil
        self.action = action
    }

    /// Small or large card — with image
    init(
        _ headline: String,
        explainer: String,
        size: AppCardSize,
        image: Image,
        height: CGFloat? = nil,
        action: (() -> Void)? = nil
    ) {
        self.size = size
        self.headline = headline
        self.explainer = explainer
        self.image = image
        self.action = action
        switch size {
        case .large: self.height = height ?? 330
        case .small: self.height = height ?? 150
        case .compact: self.height = height ?? 280
        }
    }

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    @ViewBuilder private var card: some View {
        switch size {
        case .large:
            largeBody
        case .small:
            smallBody
        case .compact:
            compactBody
        }
    }

    /// Design system in Figma sets gaps based on visual distance, while SwiftUI gaps on bounding
    /// boxes — we reduce gaps to compensate
    private var visualTextGap: CGFloat {
        Sizing.Card.Gap.text - 8
    }

    private var visualTextGapCompact: CGFloat {
        Sizing.Card.Gap.textCompact - 4
    }

    // MARK: - Large

    private var largeBody: some View {
        let imageHeight: CGFloat = 180

        return VStack(spacing: 0) {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            }
            ViewThatFits(in: .vertical) {
                textContent(headlineStyle: Typography.titleS, gap: visualTextGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(showsIndicators: false) {
                    textContent(headlineStyle: Typography.titleS, gap: visualTextGap)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, Sizing.Card.Py.bottom)
                }
                .mask(scrollFadeMask)
            }
            .padding(.horizontal, Sizing.Card.Gap.text)
            .padding(.top, Sizing.Card.Gap.imageText)
            .padding(.bottom, Sizing.Card.Py.bottom)
        }
        .frame(width: 280, height: height, alignment: .top)
        .padding(.horizontal, Sizing.Card.Px.small)
        .padding(.top, Sizing.Card.Py.top)
        .background(colors.surface.standard.elevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: - Small

    private var smallBody: some View {
        let imageWidth: CGFloat = 100

        return HStack(spacing: Sizing.Card.Gap.text) {
            ViewThatFits(in: .vertical) {
                textContent(headlineStyle: Typography.titleS, gap: visualTextGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: height - Sizing.Card.Py.small * 2, alignment: .center)
                ScrollView(showsIndicators: false) {
                    textContent(headlineStyle: Typography.titleS, gap: visualTextGap)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, Sizing.Card.Py.bottom)
                }
                .mask(scrollFadeMask)
            }
            .padding(.leading, Sizing.Card.Px.large)
            .padding(.vertical, Sizing.Card.Py.small)

            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageWidth)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .padding(.trailing, Sizing.Card.Px.small)
                    .padding(.vertical, Sizing.Card.Px.small)
            }
        }
        .frame(width: 350, height: height)
        .background(colors.surface.standard.elevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: - Compact

    private var compactBody: some View {
        textContent(headlineStyle: Typography.titleXS, gap: visualTextGapCompact)
            .frame(width: 280, alignment: .leading)
            .padding(.top, Sizing.Card.Py.compact)
            .padding(.bottom, Sizing.Card.Py.compact)
            .padding(.leading, Sizing.Card.Gap.text + Sizing.Card.Px.small)
            .padding(.trailing, Sizing.Card.Gap.text + Sizing.Card.Px.small)
            .background(colors.surface.standard.elevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: - Shared

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

    private func textContent(headlineStyle: TypographyStyle, gap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            Text(headline)
                .typography(headlineStyle)
                .foregroundStyle(colors.text.standard.base)
            Text(explainer)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
        }
    }
}

// MARK: - Previews

#Preview("Large Cards") {
    CardPreview {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.n16) {
                AppCard(
                    "Headline goes here",
                    explainer: "Explainer text goes right here.",
                    size: .large,
                    image: previewImage(colors: [.init(hex: "#A7B04E"), .init(hex: "#5C7A2E")])
                )
                AppCard(
                    "Golden hour in the hills",
                    explainer: "The light was perfect just before sunset over the ridge.",
                    size: .large,
                    image: previewImage(colors: [.init(hex: "#B39779"), .init(hex: "#7A5C3A")]),
                    action: { print("Tapped: Golden hour") }
                )
                AppCard(
                    "Quiet morning",
                    explainer: "Nothing urgent. A good day to think.",
                    size: .large,
                    image: previewImage(colors: [.init(hex: "#6B8CAE"), .init(hex: "#2E4A6A")])
                )
            }
            .padding(.horizontal, Spacing.n24)
        }
    }
    .resolveTheme()
}

#Preview("Small Cards") {
    CardPreview {
        VStack(spacing: Spacing.n16) {
            AppCard(
                "Headline goes here",
                explainer: "Explainer text",
                size: .small,
                image: previewImage(colors: [.init(hex: "#FCAF53"), .init(hex: "#E07B20")]),
                action: { print("Tapped: Headline goes here") }
            )
            AppCard(
                "Daily update",
                explainer: "Three things happened since you last checked in. It's so interesting. Check it out!",
                size: .small,
                image: previewImage(colors: [.init(hex: "#347E3E"), .init(hex: "#1A4A22")])
            )
        }
    }
    .resolveTheme()
}

#Preview("Compact Cards") {
    CardPreview {
        VStack(spacing: Spacing.n16) {
            AppCard(
                "Headline goes here",
                explainer: "Explainer text goes right here"
            )
            AppCard(
                "Quick reminder",
                explainer: "Don't forget to review the proposal before the meeting.",
                action: { print("Tapped: Quick reminder") }
            )
            AppCard(
                "System update",
                explainer: "Version 3.2 is now available with security fixes."
            )
        }
    }
    .resolveTheme()
}

@MainActor private func previewImage(colors: [Color]) -> Image {
    let renderer = ImageRenderer(content:
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(width: 600, height: 400)
    )
    return Image(uiImage: renderer.uiImage ?? UIImage())
}

private struct CardPreview<Content: View>: View {
    @Environment(\.colors) private var colors
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Spacing.n24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.surface.standard.base)
    }
}
