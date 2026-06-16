import SwiftUI

/// Plain-language explanation of how the Eigin relay works: privacy, European hosting, curated
/// models, and what a credit is. The high-level pitch lives in the sheet's description; each point
/// is an icon, headline, and short body.
struct EiginRelayInfoSheetContent: View {
    @Environment(\.colors) private var colors
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var px: CGFloat {
        sizeClass == .regular
            ? Sizing.PageLayout.HeaderGrouping.Px.tablet
            : Sizing.PageLayout.HeaderGrouping.Px.mobile
    }

    private struct InfoPoint: Identifiable {
        let icon: String
        let title: String
        let body: String
        var id: String {
            title
        }
    }

    private var points: [InfoPoint] {
        typealias strings = Localized.Provider.Eigin
        return [
            InfoPoint(icon: "lock.fill", title: strings.privacyTitle, body: strings.privacyBody),
            InfoPoint(
                icon: "globe.europe.africa.fill",
                title: strings.europeTitle,
                body: strings.europeBody
            ),
            InfoPoint(icon: "sparkles", title: strings.modelsTitle, body: strings.modelsBody),
            InfoPoint(
                icon: "eurosign.circle.fill",
                title: strings.creditTitle,
                body: strings.creditBody
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n32) {
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: Spacing.n8) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.n8) {
                        Image(systemName: point.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(colors.text.standard.base)
                        Text(point.title)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                    }
                    Text(point.body)
                        .typography(Typography.description)
                        .foregroundStyle(colors.text.standard.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, px)
    }
}
