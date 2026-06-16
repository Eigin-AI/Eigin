import SwiftUI

/// The Eigin credits home: shows the user's summed credit balance, a way to buy more, and
/// plain-language information about how the relay keeps inference private.
///
/// Reached from the permanent Eigin row in ``ConnectionsView``, mirroring how On-Device opens
/// ``LocalProviderView``.
struct EiginProviderView: View {
    @Environment(\.colors) private var colors
    @State private var model = EiginCreditsModel()
    @State private var showPurchase = false
    @State private var showInfo = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.n40)
            balance
            Spacer(minLength: Spacing.n40)
            bottomGroup
                .padding(.horizontal, Spacing.n24)
                .padding(.bottom, Spacing.n32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle("Eigin", style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
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

    /// Pitch card, primary action, and the "learn more" button, anchored at the bottom.
    private var bottomGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            AppCard(
                Localized.Provider.Eigin.blurbTitle,
                explainer: Localized.Provider.Eigin.blurbBody,
                width: .infinity
            )
            AppButton(Localized.Provider.Eigin.getMoreCredits, variant: .spot) {
                showPurchase = true
            }
            AppSubtleActionButton(
                Localized.Provider.Eigin.learnHowItWorks,
                icon: Image(systemName: "chevron.right")
            ) {
                showInfo = true
            }
        }
    }

    private var balance: some View {
        VStack(spacing: Spacing.n8) {
            Text(verbatim: "\(model.totalCredits)")
                .typography(Typography.display)
                .foregroundStyle(colors.text.standard.base)
                .contentTransition(.numericText())
            HStack(spacing: Spacing.n8) {
                Text(Localized.Provider.Eigin.creditsCaption)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.muted)
                refreshButton
            }
        }
        .animation(Animations.smooth, value: model.totalCredits)
    }

    /// Fixed-size refresh control beside the caption. Swaps the circular-arrow glyph for a spinner
    /// while refreshing so the surrounding text never shifts.
    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            ZStack {
                if model.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing)
    }
}

#Preview {
    NavigationStack {
        EiginProviderView()
    }
    .previewEnvironment()
}
