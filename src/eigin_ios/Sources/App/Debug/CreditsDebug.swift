#if DEBUG
import Factory
import SwiftUI

/// Development-only panel for exercising the credit purchase → redeem → wallet flow against the
/// (staging) relay. Run on a physical device signed into a sandbox Apple Account.
struct CreditsDebug: View {
    @Environment(\.colors) private var colors

    @Injected(\.creditsService) private var creditsService
    @Injected(\.creditWalletManager) private var walletManager
    @Injected(\.keychainService) private var keychainService

    /// Direct store access so we can delete wallets here to simulate running out of credits. The
    /// production ``CreditWalletManager`` deliberately exposes no removal, so this stays
    /// debug-only.
    private var store: CreditWalletStore {
        CreditWalletStore(keychain: keychainService)
    }

    @State private var wallets: [CreditWallet] = []
    @State private var products: [PurchasableCredit] = []
    @State private var isBusy = false
    @State private var error: String?
    @State private var diagnostics: String?

    var body: some View {
        List {
            Section("Actions") {
                Button {
                    Task {
                        isBusy = true
                        await loadProducts()
                        isBusy = false
                    }
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "bag", color: .green)
                        Text("Refresh products")
                        Spacer()
                        if isBusy { ProgressView() }
                    }
                }
                .disabled(isBusy)

                Button {
                    Task {
                        isBusy = true
                        await walletManager.refreshBalances()
                        reload()
                        isBusy = false
                    }
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "arrow.clockwise", color: .blue)
                        Text("Refresh balances")
                    }
                }
                .disabled(isBusy)

                Button {
                    walletManager.evictEmpty()
                    reload()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "trash", color: .orange)
                        Text("Evict empty wallets")
                    }
                }

                Button(role: .destructive) {
                    store.replaceAll([])
                    reload()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "trash.slash", color: .red)
                        Text("Delete all wallets")
                    }
                }
                .disabled(wallets.isEmpty)

                Button {
                    Task {
                        isBusy = true
                        diagnostics = await runDiagnostics()
                        isBusy = false
                    }
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "stethoscope", color: .purple)
                        Text("Diagnose StoreKit")
                        Spacer()
                        if isBusy { ProgressView() }
                    }
                }
                .disabled(isBusy)

                if let diagnostics {
                    Text(diagnostics)
                        .font(Typography.miniLabel.font.monospaced())
                        .foregroundStyle(colors.text.standard.muted)
                        .textSelection(.enabled)
                }

                if let error {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "xmark.circle", color: .red)
                        Text(error)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Products") {
                if products.isEmpty {
                    Text("No products — tap Refresh products")
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                } else {
                    ForEach(products) { product in
                        Button {
                            buyCredits(productID: product.id)
                        } label: {
                            HStack(spacing: Spacing.n8) {
                                SettingsIcon(systemName: "creditcard.fill", color: .green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName)
                                    Text("\(product.credits) cr · \(product.id)")
                                        .font(Typography.miniLabel.font.monospaced())
                                        .foregroundStyle(colors.text.standard.muted)
                                }
                                Spacer()
                                Text(product.displayPrice)
                                    .font(Typography.miniLabel.font.bold())
                            }
                        }
                        .disabled(isBusy)
                    }
                }
            }

            Section("Wallets") {
                if wallets.isEmpty {
                    Text("No wallets")
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                } else {
                    ForEach(wallets) { wallet in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(maskToken(wallet.token))
                                    .font(Typography.miniLabel.font.monospaced())
                                Spacer()
                                Text("\(wallet.credits) cr")
                                    .font(Typography.miniLabel.font.bold())
                            }
                            Text(wallet.status.rawValue)
                                .typography(Typography.miniLabel)
                                .foregroundStyle(colors.text.standard.muted)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.remove(token: wallets[index].token)
                        }
                        reload()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle("Credits")
        .onAppear(perform: reload)
        .task { await loadProducts() }
    }

    private func buyCredits(productID: String) {
        isBusy = true
        error = nil
        Task {
            do {
                _ = try await creditsService.purchaseCredits(productID: productID)
            } catch {
                self.error = error.localizedDescription
            }
            reload()
            isBusy = false
        }
    }

    private func loadProducts() async {
        error = nil
        do {
            products = try await creditsService.availableProducts()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reload() {
        wallets = walletManager.wallets()
    }

    /// Fetch the relay catalog and resolve it against StoreKit so we can tell a config/code problem
    /// apart from App Store Connect not yet vending a product (agreement/banking, product state, or
    /// propagation).
    private func runDiagnostics() async -> String {
        var lines: [String] = []
        do {
            let products = try await creditsService.availableProducts()
            lines.append("Resolved \(products.count) purchasable product(s)")
            for product in products {
                lines.append("• \(product.id) — \(product.displayPrice) (\(product.credits) cr)")
            }
            if products.isEmpty {
                lines.append(
                    "Empty result → either the relay catalog is empty or App Store Connect isn't "
                        + "vending these IDs yet (agreement/banking pending, product state, or "
                        + "propagation delay)."
                )
            }
        } catch {
            lines.append("Fetch threw: \(error.localizedDescription)")
        }

        return lines.joined(separator: "\n")
    }

    private func maskToken(_ token: String) -> String {
        "\(token.prefix(11))…"
    }
}
#endif
