import Factory
import SwiftData
import SwiftUI

/// Detail view for a connected integration: account, granted capabilities, disconnect.
struct IntegrationDetail: View {
    let integration: Integration
    @Injected(\.integrationManager) private var integrationManager
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showRemoveConfirmation = false

    private var type: IntegrationType? {
        BundledIntegrationType.type(forID: integration.typeID)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: integration.accountLabel,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    infoCard
                    capabilitiesCard
                    removeCard
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(integration.accountLabel, isPresented: $showRemoveConfirmation) {
            Button(Localized.Ui.remove, role: .destructive) { remove() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        }
    }

    private var infoCard: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                infoRow(
                    label: Localized.Common.Fields.name,
                    value: type?.displayName ?? integration.typeID
                )
                Divider().padding(.leading, Spacing.n24)
                infoRow(label: Localized.Ui.email, value: integration.accountLabel)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.n16) {
            Text(label)
                .typography(Typography.titleXS)
                .foregroundStyle(colors.text.standard.base)
            Spacer()
            Text(value)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
    }

    /// All capabilities the type can provide, each flagged with whether this
    /// specific connection actually granted it — Google's consent screen lets
    /// scopes be denied individually, so "connected" doesn't imply "fully granted".
    private var allCapabilities: [(capability: Capability, granted: Bool)] {
        let granted = Set(integration.grantedCapabilities)
        let all = type?
            .providedCapabilities ??
            Set(integration.grantedCapabilities.compactMap(Capability.init))
        return all.sorted { $0.rawValue < $1.rawValue }.map { ($0, granted.contains($0.rawValue)) }
    }

    private var capabilitiesCard: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Ui.integrations)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(
                        Array(allCapabilities.enumerated()),
                        id: \.element.capability
                    ) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, Spacing.n24)
                        }
                        HStack {
                            Text(entry.capability.rawValue.titleCased)
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.text.standard.base)
                            Spacer()
                            Image(systemName: entry
                                .granted ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(entry.granted ? .green : colors.text.standard
                                    .muted)
                        }
                        .padding(.horizontal, Spacing.n24)
                        .padding(.vertical, Spacing.n16)
                    }
                }
            }

            if allCapabilities.contains(where: { !$0.granted }) {
                Text(
                    "Not granted — disconnect and reconnect this integration to approve the permissions you skipped."
                )
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.n8)
            }

            // Tool-level permissions for this capability are managed in the
            // main permissions screen, grouped like any other external tool —
            // connecting an integration doesn't hide them from user control.
        }
    }

    private var removeCard: some View {
        AppButton(Localized.Ui.remove, variant: .destructive) {
            showRemoveConfirmation = true
        }
    }

    private func remove() {
        integrationManager.disconnect(integration)
        modelContext.delete(integration)
        dismiss()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}
