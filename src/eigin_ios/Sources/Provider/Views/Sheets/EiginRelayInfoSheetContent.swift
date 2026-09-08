import SwiftUI

/// How the relay works, in plain language: privacy, European hosting,
/// curated models, and what a credit buys. The points are rows in a card, the
/// same as the facts on the screen that opens this sheet — they answer the
/// same kind of question, so they are told the same way.
struct EiginRelayInfoSheetContent: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            AppContentGroup {
                point(
                    icon: Iconography.Functional.lock,
                    title: Localized.Provider.Eigin.privacyTitle,
                    body: Localized.Provider.Eigin.privacyBody
                )
                RowHairline()
                point(
                    icon: Iconography.Functional.globe,
                    title: Localized.Provider.Eigin.europeTitle,
                    body: Localized.Provider.Eigin.europeBody
                )
                RowHairline()
                point(
                    icon: Iconography.Functional.sparkles,
                    title: Localized.Provider.Eigin.modelsTitle,
                    body: Localized.Provider.Eigin.modelsBody
                )
                RowHairline()
                point(
                    icon: Iconography.Functional.euro,
                    title: Localized.Provider.Eigin.creditTitle,
                    body: Localized.Provider.Eigin.creditBody
                )
            }
            .padding(.horizontal, Spacing.n16)
        }
    }

    private func point(icon: Image, title: String, body: String) -> some View {
        AppRow(
            AppRowSpec(
                title: title,
                description: body,
                icon: icon,
                accessory: .none
            )
        )
    }
}

#Preview {
    EiginRelayInfoSheetContent()
        .previewEnvironment()
}
