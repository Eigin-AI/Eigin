import SwiftUI

/// Purchase options for Eigin credits. Each row buys a `PurchasableCredit`;
/// the relay grants the credits and the wallet is stored. The pricing note
/// lives in the sheet's description, restore sits under the packs as its own
/// quieter action. Three prices are a list to compare, not three separate
/// offers — so one card of rows, with the price pills sharing a width so the
/// right edge is one line.
struct GetCreditsSheetContent: View {
    @Environment(\.colors) private var colors
    @Environment(\.horizontalSizeClass) private var sizeClass
    let model: EiginCreditsModel
    let onPurchased: () -> Void

    /// The packs card runs to the same page inset as every other card on
    /// these screens; the sheet header keeps its own deeper inset.
    private var px: CGFloat {
        Spacing.n16
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.n12) {
                if model.products.isEmpty {
                    emptyState
                } else {
                    packs
                }

                restoreButton

                if let error = model.error {
                    Text(error)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.error)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, px)
        }
        .task { await model.loadProductsIfNeeded() }
    }

    // MARK: - Packs

    private var packs: some View {
        AppContentGroup {
            ForEach(model.products) { product in
                productRow(product)
            }
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
            .padding(.vertical, Spacing.n16)
            .padding(.horizontal, Spacing.n24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isPurchasing || model.isRestoring)
    }

    /// One column of prices rather than three pills of different widths: the
    /// minimum is content-box, with tabular numerals keeping the right edge
    /// one line. The pill never disappears: while its own purchase runs, the
    /// spinner lives inside it, so the row holds its shape.
    private func priceTag(_ product: PurchasableCredit) -> some View {
        HStack {
            if model.purchasingID == product.id {
                ProgressView()
                    .controlSize(.small)
                    .tint(colors.text.button.onSpot)
            } else {
                Text(product.displayPrice)
                    .typography(Typography.buttonSmall)
                    .monospacedDigit()
                    .foregroundStyle(colors.text.button.onSpot)
            }
        }
        .padding(.horizontal, Spacing.n20)
        .padding(.vertical, Spacing.n12)
        .frame(minWidth: 65)
        .background(model.purchasingID == product.id ? colors.button.spot.base.opacity(0.4) : colors
            .button.spot.base)
        .clipShape(Capsule())
    }

    // MARK: - Around the packs

    /// Re-redeem the account's purchase history so credits survive a
    /// reinstall. Lifted off the packs so it reads as its own secondary
    /// action, inset to start on the same column the pack labels do.
    @ViewBuilder
    private var restoreButton: some View {
        if model.hasLoadedProducts {
            Button {
                Task {
                    if await model.restorePurchases() { onPurchased() }
                }
            } label: {
                HStack(spacing: Spacing.n4) {
                    if model.isRestoring {
                        // The spinner takes the arrows' place: same slot, no
                        // doubling up, and the text never shifts.
                        ProgressView().controlSize(.small)
                            .tint(colors.text.standard.disabled)
                    } else {
                        Iconography.Functional.refresh
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    Text(Localized.Provider.Eigin.restoreCredits)
                        .typography(Typography.note)
                        .foregroundStyle(
                            model.isRestoring
                                ? colors.text.standard.disabled
                                : colors.text.standard.muted
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(model.isPurchasing || model.isRestoring)
            // Lifted off the packs onto the pack-label column.
            .padding(.top, Spacing.n16)
            .padding(.horizontal, Spacing.n24)
        }
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
}

#Preview {
    GetCreditsSheetContent(model: EiginCreditsModel(), onPurchased: {})
        .previewEnvironment()
}
