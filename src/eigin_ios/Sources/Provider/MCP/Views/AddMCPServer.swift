import Factory
import SwiftData
import SwiftUI

/// Form for adding a new MCP server configuration.
/// Auto-detects whether a server is open or requires OAuth 2.1 authentication.
struct AddMCPServer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService
    @Injected(\.mcpServerManager) private var mcpServerManager
    @Injected(\.mcpOAuthService) private var mcpOAuthService

    @State private var name = ""
    @State private var url = ""
    @State private var phase: AuthPhase = .idle
    @State private var discoveredToolNames: [String] = []
    @State private var detectedAuthType: MCPAuthType = .none

    // Client credentials — shown when server requires OAuth but has no dynamic registration
    @State private var clientID = ""
    @State private var clientSecret = ""

    /// Temporary server ID used during OAuth — Keychain tokens are stored under
    /// this ID during authorization. On save, we migrate them to the real server ID.
    @State private var tempServerID = UUID()
    @State private var oauthConfig: OAuthConfiguration?

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isCredentialsValid: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Settings.Action.addMcpServer,
                leading: {
                    AppActionButton(
                        icon: Image(systemName: "xmark"),
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                },
                trailing: {
                    trailingAction
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    // Server fields
                    VStack(spacing: Spacing.n16) {
                        AppTextInput(
                            label: Localized.Common.Fields.name,
                            text: $name
                        )
                        AppTextInput(
                            label: Localized.Common.Fields.serverUrl,
                            text: $url
                        )
                        HStack(alignment: .top, spacing: Spacing.n8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(colors.text.standard.muted)
                                .font(.system(size: 14))
                            Text(Localized.Mcp.Setup.requirement)
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.n8)
                    }

                    // Phase-specific content
                    phaseContent

                    // Discovered tools
                    if !discoveredToolNames.isEmpty || phase == .done {
                        toolsCard
                    }
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
    }

    // MARK: - Trailing Action

    @ViewBuilder
    private var trailingAction: some View {
        switch phase {
        case .probing, .oauthAuthorizing, .connecting:
            ProgressView()
                .padding(.trailing, Spacing.n4)
        case .done:
            AppActionButton(
                icon: Image(systemName: "plus"),
                variant: .open,
                size: .medium,
                action: { saveServer() }
            )
        case .needsCredentials:
            AppActionButton(
                icon: Image(systemName: "arrow.right"),
                variant: .open,
                size: .medium,
                action: { continueWithCredentials() }
            )
            .disabled(!isCredentialsValid)
        default:
            AppActionButton(
                icon: Image(systemName: "arrow.right"),
                variant: .open,
                size: .medium,
                action: { startConnection() }
            )
            .disabled(!isFormValid)
        }
    }

    // MARK: - Phase Content

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .probing:
            statusCard {
                HStack(spacing: Spacing.n8) {
                    ProgressView()
                    Text(Localized.Mcp.Status.checking)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }

        case .oauthAuthorizing:
            statusCard {
                HStack(spacing: Spacing.n8) {
                    ProgressView()
                    Text(Localized.Auth.waiting)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }

        case .connecting:
            statusCard {
                HStack(spacing: Spacing.n8) {
                    ProgressView()
                    Text(Localized.Network.connecting)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }

        case .needsCredentials:
            VStack(spacing: Spacing.n16) {
                sectionLabel(Localized.Mcp.Setup.clientCredentials)

                AppCardSurface(padding: 0) {
                    VStack(spacing: 0) {
                        AppTextInput(
                            label: Localized.Common.Fields.clientId,
                            text: $clientID
                        )
                        .padding(.horizontal, Spacing.n24)
                        .padding(.top, Spacing.n16)
                        .padding(.bottom, Spacing.n8)

                        AppTextInput(
                            label: Localized.Common.Fields.clientSecret,
                            text: $clientSecret,
                            isSecure: true
                        )
                        .padding(.horizontal, Spacing.n24)
                        .padding(.top, Spacing.n8)
                        .padding(.bottom, Spacing.n16)
                    }
                }

                Text(Localized.Mcp.Setup.manualCredentialsHint)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.n8)
            }

        case .done:
            EmptyView()

        case .error(let message):
            AppCardSurface {
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
        }
    }

    // MARK: - Tools Card

    private var toolsCard: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Mcp.tools)

            AppCardSurface(padding: 0) {
                if discoveredToolNames.isEmpty {
                    HStack {
                        Text(Localized.Mcp.noToolsDiscovered)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.n24)
                    .padding(.vertical, Spacing.n16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(discoveredToolNames.enumerated()),
                            id: \.element
                        ) { index, toolName in
                            if index > 0 {
                                Divider().padding(.leading, Spacing.n24)
                            }
                            HStack {
                                Text(toolName)
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.base)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.n24)
                            .padding(.vertical, Spacing.n16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusCard(@ViewBuilder content: @escaping () -> some View) -> some View {
        AppCardSurface {
            content()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }

    // MARK: - Connection Flow

    private func startConnection() {
        phase = .probing
        discoveredToolNames = []
        tempServerID = UUID()
        oauthConfig = nil
        detectedAuthType = .none

        Task {
            guard let endpoint = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                phase = .error("Invalid URL")
                Haptics.error()
                return
            }

            do {
                // Phase 1: Probe for OAuth
                let config = try await mcpOAuthService.discoverOAuth(for: endpoint)

                if let config {
                    oauthConfig = config
                    detectedAuthType = .oauth

                    if config.needsClientCredentials {
                        // Server requires OAuth but has no dynamic registration.
                        // Ask the user for client credentials.
                        phase = .needsCredentials
                        return
                    }

                    // Dynamic registration succeeded — proceed to authorize
                    try await authorizeAndConnect(config: config, endpoint: endpoint)
                } else {
                    // Open server — connect directly
                    try await connectAndDiscover(endpoint: endpoint, authProvider: NoAuthProvider())
                }
            } catch MCPOAuthError.userCancelled {
                phase = .idle
            } catch {
                phase = .error(error.localizedDescription)
                Haptics.error()
            }
        }
    }

    /// Called when user fills in client credentials and taps "Authorize".
    private func continueWithCredentials() {
        guard var config = oauthConfig else { return }

        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        config = config.withClientCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespaces),
            clientSecret: secret.isEmpty ? nil : secret
        )
        oauthConfig = config

        phase = .oauthAuthorizing

        Task {
            guard let endpoint = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                phase = .error("Invalid URL")
                Haptics.error()
                return
            }

            do {
                try await authorizeAndConnect(config: config, endpoint: endpoint)
            } catch MCPOAuthError.userCancelled {
                // Return to credentials form so they can retry
                phase = .needsCredentials
            } catch {
                phase = .error(error.localizedDescription)
                Haptics.error()
            }
        }
    }

    /// Runs OAuth authorization then connects to verify.
    private func authorizeAndConnect(config: OAuthConfiguration, endpoint: URL) async throws {
        phase = .oauthAuthorizing
        _ = try await mcpOAuthService.authorize(config: config, serverID: tempServerID)

        let authProvider = OAuthAuthProvider(oauthService: mcpOAuthService, serverID: tempServerID)
        try await connectAndDiscover(endpoint: endpoint, authProvider: authProvider)
    }

    /// Connects to the server, discovers tools, then disconnects the test connection.
    private func connectAndDiscover(endpoint: URL, authProvider: any MCPAuthProvider) async throws {
        phase = .connecting

        let connection = MCPServerConnection(
            serverName: name,
            endpoint: endpoint,
            authProvider: authProvider
        )

        try await connection.connect()
        let tools = await connection.tools()
        discoveredToolNames = tools.map(\.name)

        // Disconnect the test connection — the real connection
        // will be established by MCPServerManager after saving.
        await connection.disconnect()

        phase = .done
        Haptics.success()
    }

    // MARK: - Save

    private func saveServer() {
        let server = MCPServer(
            name: name.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: detectedAuthType
        )
        server.cachedToolNames = discoveredToolNames

        // Store OAuth endpoint info on the model for reference
        if let config = oauthConfig {
            server.oauthClientID = config.clientID
            server.oauthAuthURL = config.authorizationEndpoint.absoluteString
            server.oauthTokenURL = config.tokenEndpoint.absoluteString
            server.oauthScopes = config.scopes?.joined(separator: " ")
        }

        modelContext.insert(server)

        // Migrate Keychain tokens from tempServerID to the real server.id
        if detectedAuthType == .oauth {
            migrateKeychainTokens(from: tempServerID, to: server.id)
        }

        dismiss()
    }

    private func migrateKeychainTokens(from oldID: UUID, to newID: UUID) {
        for suffix in MCPServer.keychainSuffixes {
            let oldKey = keychainService.mcpKey(for: oldID, suffix: suffix)
            if let value = keychainService.read(key: oldKey) {
                keychainService.save(
                    key: keychainService.mcpKey(for: newID, suffix: suffix),
                    value: value
                )
                keychainService.delete(key: oldKey)
            }
        }
    }
}

// MARK: - Auth Phase

private enum AuthPhase: Equatable {
    case idle
    case probing
    case needsCredentials // Server needs OAuth but has no dynamic registration
    case oauthAuthorizing
    case connecting
    case done
    case error(String)
}
