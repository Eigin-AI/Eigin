import SwiftUI

/// Purchase options for Eigin credits. Each row buys a `PurchasableCredit`; the relay grants the
/// credits and the wallet is stored. Dismisses on a successful purchase. The pricing note lives in
/// the sheet's description.
struct GetCreditsSheetContent: View {
    @Environment(\.colors) private var colors
    @Environment(\.horizontalSizeClass) private var sizeClass
    let model: EiginCreditsModel
    let onPurchased: () -> Void

    private var px: CGFloat {
        sizeClass == .regular
            ? Sizing.PageLayout.HeaderGrouping.Px.tablet
            : Sizing.PageLayout.HeaderGrouping.Px.mobile
    }

    var body: some View {
        VStack(spacing: Spacing.n12) {
            if model.products.isEmpty {
                emptyState
            } else {
                ForEach(model.products) { product in
                    productRow(product)
                }
            }

            if let error = model.error {
                Text(error)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.n8)
            }
        }
        .padding(.horizontal, px)
        .task { await model.loadProductsIfNeeded() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.hasLoadedProducts {
            Text(Localized.Provider.Eigin.noProducts)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)
        } else {
            ProgressView()
                .padding(.vertical, Spacing.n32)
        }
    }

    private func productRow(_ product: PurchasableCredit) -> some View {
        Button {
            Task {
                if await model.purchase(product.id) { onPurchased() }
            }
        } label: {
            HStack(spacing: Spacing.n16) {
                Text(Localized.Provider.Eigin.creditAmount("\(product.credits)"))
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                Spacer()
                priceTag(product)
            }
            .padding(.horizontal, Spacing.n24)
            .padding(.vertical, Spacing.n20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.button.standard.secondary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .disabled(model.isPurchasing)
    }

    private func priceTag(_ product: PurchasableCredit) -> some View {
        Group {
            if model.purchasingID == product.id {
                ProgressView()
                    .controlSize(.small)
                    .tint(colors.text.button.onSpot)
            } else {
                Text(product.displayPrice)
                    .typography(Typography.buttonSmall)
                    .foregroundStyle(colors.text.button.onSpot)
            }
        }
        .padding(.horizontal, Spacing.n20)
        .padding(.vertical, Spacing.n12)
        .background(colors.button.spot.base)
        .clipShape(Capsule())
    }
}
