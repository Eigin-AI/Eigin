import SwiftUI

/// In-chat recovery for an out-of-credits error on the Eigin relay.
///
/// Shows the error and a "Get more credits" action that buys credits inline. It watches the wallet
/// balance, so once a purchase lands it flips to a reassuring "you're good to go" state instead of
/// leaving the stale error on screen until the next send.
struct CreditsRecoveryCard: View {
    /// The originating error, used for the out-of-credits copy.
    let error: ConnectionError

    @State private var model = EiginCreditsModel()
    @State private var showPurchase = false

    private var hasCredits: Bool {
        model.totalCredits > 0
    }

    var body: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            if hasCredits {
                AppCard(
                    Localized.Provider.Eigin.creditsReadyTitle,
                    explainer: Localized.Provider.Eigin.creditsReadyBody
                )
            } else {
                AppCard(error.title, explainer: error.suggestion)
                AppButton(Localized.Provider.Eigin.getMoreCredits, variant: .spot) {
                    showPurchase = true
                }
            }
        }
        .task { await model.refresh() }
        .appSheet(
            isPresented: $showPurchase,
            title: Localized.Provider.Eigin.getCreditsTitle,
            description: Localized.Provider.Eigin.getCreditsDescription,
            detents: [.medium, .large]
        ) {
            GetCreditsSheetContent(model: model) { showPurchase = false }
        }
    }
}
