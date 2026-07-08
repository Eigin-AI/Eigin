import Factory
import SwiftData
import SwiftUI

/// Sheet for connecting a new integration: pick a type, run its auth flow, save.
struct AddIntegration: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors
    @Injected(\.integrationOAuthService) private var oauthService
    @Injected(\.integrationManager) private var integrationManager
    @Query(filter: #Predicate<Integration> { $0.isEnabled
    }) private var existingIntegrations: [Integration]

    @State private var phase: Phase = .picking
    @State private var partialGrantWarning: String?

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Settings.Action.addIntegration,
                leading: {
                    AppActionButton(
                        icon: Image(systemName: "xmark"),
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    switch phase {
                    case .picking:
                        typesList
                    case .authorizing:
                        statusCard {
                            HStack(spacing: Spacing.n8) {
                                ProgressView()
                                Text(Localized.Auth.waiting)
                                    .typography(Typography.tag)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                        }
                    case .error(let message):
                        statusCard {
                            VStack(alignment: .leading, spacing: Spacing.n8) {
                                Label(
                                    Localized.Errors.Connection.title,
                                    systemImage: "exclamationmark.triangle"
                                )
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.text.standard.error)
                                Text(message)
                                    .typography(Typography.tag)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                        }
                        typesList
                    }
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .alert(
            Localized.Ui.integrations,
            isPresented: Binding(
                get: { partialGrantWarning != nil },
                set: { if !$0 { partialGrantWarning = nil } }
            )
        ) {
            Button("OK") { dismiss() }
        } message: {
            Text(partialGrantWarning ?? "")
        }
    }

    private var typesList: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                ForEach(
                    Array(BundledIntegrationType.all.enumerated()),
                    id: \.element.id
                ) { index, type in
                    if index > 0 {
                        Divider().padding(.leading, Spacing.n24)
                    }
                    Button { connect(type) } label: {
                        HStack(spacing: Spacing.n16) {
                            Image(systemName: type.systemImage)
                                .foregroundStyle(colors.accent)
                            VStack(alignment: .leading, spacing: Spacing.n4) {
                                Text(type.displayName)
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.base)
                                Text(type.description)
                                    .typography(Typography.tag)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.n24)
                        .padding(.vertical, Spacing.n16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statusCard(@ViewBuilder content: @escaping () -> some View) -> some View {
        AppCardSurface { content() }
    }

    private func connect(_ type: IntegrationType) {
        // One provider per capability for now: connecting a second integration
        // that would provide a capability another connection already grants
        // means two same-named tools in one registry with no way to address a
        // specific account. Disconnect the existing one first instead.
        let alreadyConnected = integrationManager
            .connectedCapabilities(integrations: existingIntegrations)
        let conflicts = type.providedCapabilities.intersection(alreadyConnected)
        guard conflicts.isEmpty else {
            let names = conflicts.map(\.rawValue.titleCased).joined(separator: ", ")
            phase = .error(
                "\(names) is already provided by a connected integration. Disconnect it first to connect a different one."
            )
            return
        }

        guard case .oauth(let configFactory) = type.authKind else { return }
        let config = configFactory()
        // Client id comes from a build-time secret (see `.env` / project.yml) —
        // if it's missing, authorize() would still launch a browser session
        // that can never complete (Google rejects an empty client_id), which
        // reads to the user as a silent hang. Fail fast with a clear reason.
        guard !config.clientID.isEmpty else {
            phase = .error(
                "\(type.displayName) isn't configured in this build — its OAuth client id is missing."
            )
            return
        }
        phase = .authorizing

        Task {
            let integrationID = UUID()
            do {
                let accessToken = try await oauthService.authorize(
                    config: config,
                    integrationID: integrationID
                )
                let accountLabel = await type.accountLabel(accessToken) ?? type.displayName

                // Google's consent screen lets the user deny individual scopes, so
                // don't assume every requested capability was granted.
                let grantedScopes = oauthService.grantedScopes(for: integrationID)
                let grantedCapabilities = type.grantedCapabilities(fromGrantedScopes: grantedScopes)

                // Reuse the id authorize() already stored tokens under — no need to
                // migrate keychain keys to a separately-minted model id.
                let integration = Integration(
                    id: integrationID,
                    typeID: type.id,
                    accountLabel: accountLabel,
                    grantedCapabilities: grantedCapabilities.map(\.rawValue)
                )
                modelContext.insert(integration)

                let ungranted = type.providedCapabilities.subtracting(grantedCapabilities)
                if !ungranted.isEmpty {
                    let names = ungranted.map(\.rawValue.titleCased).joined(separator: ", ")
                    partialGrantWarning =
                        "\(accountLabel) is connected, but you didn't grant: \(names). The agent won't be able to use those until you reconnect and approve them."
                } else {
                    Haptics.success()
                    dismiss()
                }
            } catch IntegrationOAuthError.userCancelled {
                phase = .picking
            } catch {
                phase = .error(error.localizedDescription)
                Haptics.error()
            }
        }
    }

    private enum Phase: Equatable {
        case picking
        case authorizing
        case error(String)
    }
}
