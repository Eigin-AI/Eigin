import SwiftUI

/// The Eigin Relay screen: the balance as the first fact, what the relay is,
/// and the one button that buys more.
///
/// Reached from the permanent Eigin Relay row in ``ConnectionsView``. An
/// empty account is the one state that stops Eigin working, so the header
/// says so and the button below answers it — the notice never carries its own
/// action beyond being a shortcut to it.
struct EiginProviderView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var model = EiginCreditsModel()
    @State private var showPurchase = false
    @State private var showInfo = false

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Provider.Eigin.title,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            AppAnchoredScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    AppIdentityHeader(
                        name: Localized.Provider.Eigin.title,
                        kind: Localized.Provider.Eigin.rowSubtitle,
                        state: connectionState,
                        status: statusLabel
                    ) {
                        AppBrandAvatar(size: 64)
                    }

                    if let notice { notice }

                    facts

                    Spacer(minLength: 0)

                    AppButton(Localized.Provider.Eigin.getMoreCredits, variant: .spot) {
                        showPurchase = true
                    }
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .animation(Animations.smooth, value: model.totalCredits)
        .task { await model.onAppear() }
        .appSheet(
            isPresented: $showPurchase,
            title: Localized.Provider.Eigin.getCreditsTitle,
            description: Localized.Provider.Eigin.getCreditsDescription,
            detents: [.medium, .large]
        ) {
            GetCreditsSheetContent(model: model) { showPurchase = false }
        }
        .appSheet(
            isPresented: $showInfo,
            title: Localized.Provider.Eigin.infoTitle,
            description: Localized.Provider.Eigin.infoDescription,
            fitsContent: true
        ) {
            EiginRelayInfoSheetContent()
        }
    }

    // MARK: - Credit state

    /// Empty is yours to fix (the button answers it); low is a heads-up;
    /// anything else is simply up.
    private enum CreditState {
        case empty
        case runningLow
        case fine
    }

    private var creditState: CreditState {
        switch model.totalCredits {
        case ..<1: .empty
        case ..<100: .runningLow
        default: .fine
        }
    }

    private var connectionState: ConnectionState {
        creditState == .empty ? .attention : .connected
    }

    private var statusLabel: String {
        switch creditState {
        case .empty: Localized.Provider.Relay.Status.outOfCredits
        default: Localized.Provider.Relay.Status.ready
        }
    }

    /// The notice raises the problem; the screen's primary button answers it.
    private var notice: AppNotice? {
        switch creditState {
        case .empty:
            AppNotice(
                tone: .warning,
                title: Localized.Provider.Relay.Notice.pausedTitle,
                body: Localized.Provider.Relay.Notice.pausedBody,
                action: { showPurchase = true }
            )
        case .runningLow:
            AppNotice(
                tone: .info,
                title: Localized.Provider.Relay.Notice.runningLowTitle,
                body: Localized.Provider.Relay.Notice.runningLowBody
            )
        case .fine:
            nil
        }
    }

    // MARK: - Facts

    private var facts: some View {
        AppRowsGroup(
            footnote: Localized.Provider.Relay.factsFootnote,
            rows: [
                AppRowSpec(
                    title: Localized.Provider.Relay.Facts.credits,
                    value: "\(model.totalCredits)",
                    accessory: .none
                ),
                AppRowSpec(
                    title: Localized.Provider.Relay.Facts.hostedIn,
                    value: Localized.Provider.Relay.Facts.hostedInValue,
                    accessory: .none
                ),
                AppRowSpec(
                    title: Localized.Provider.Relay.Facts.conversationsStored,
                    value: Localized.Provider.Relay.Facts.conversationsStoredValue,
                    accessory: .none
                ),
                AppRowSpec(
                    title: Localized.Provider.Relay.Facts.howItWorks,
                    tone: .muted,
                    action: { showInfo = true }
                ),
            ]
        )
    }
}

#Preview {
    NavigationStack {
        EiginProviderView()
    }
    .previewEnvironment()
}
