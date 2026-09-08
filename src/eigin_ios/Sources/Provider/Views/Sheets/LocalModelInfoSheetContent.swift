import SwiftUI

/// What running on the phone buys and costs, in the same card of rows the
/// relay sheet uses: the screen states the facts, this answers the question
/// behind them.
struct LocalModelInfoSheetContent: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            AppContentGroup {
                point(
                    icon: Iconography.Functional.Speed.fast,
                    title: Localized.Provider.Local.Info.offlineTitle,
                    body: Localized.Provider.Local.Info.offlineBody
                )
                RowHairline()
                point(
                    icon: Iconography.Functional.hand,
                    title: Localized.Provider.Local.Info.chosenTitle,
                    body: Localized.Provider.Local.Info.chosenBody
                )
                RowHairline()
                point(
                    icon: Iconography.Functional.sparkles,
                    title: Localized.Provider.Local.Info.smallerTitle,
                    body: Localized.Provider.Local.Info.smallerBody
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
    LocalModelInfoSheetContent()
        .previewEnvironment()
}
