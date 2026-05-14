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
        NavigationStack {
            Form {
                Section {
                    TextField(Localized.Common.Fields.name, text: $name)
                        .autocorrectionDisabled()

                    TextField(Localized.Common.Fields.serverUrl, text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    HStack(alignment: .top, spacing: Spacing.n8) {
                        Image(systemName: "info.circle")
                        Text(Localized.Mcp.Setup.requirement)
                    }
                    .padding(.top, Spacing.n8)
                }

                statusSection

                if phase == .needsCredentials {
                    Section {
                        TextField(Localized.Common.Fields.clientId, text: $clientID)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        SecureField(Localized.Common.Fields.clientSecret, text: $clientSecret)
                            .autocorrectionDisabled()
                    } header: {
                        Text(Localized.Mcp.Setup.clientCredentials)
                    } footer: {
                        Text(Localized.Mcp.Setup.manualCredentialsHint)
                            .padding(.top, Spacing.n8)
                    }
                }

                if !discoveredToolNames.isEmpty || phase == .done {
                    Section(Localized.Mcp.tools) {
                        if discoveredToolNames.isEmpty {
                            Text(Localized.Mcp.noToolsDiscovered)
                                .foregroundStyle(colors.text.standard.muted)
                        } else {
                            ForEach(discoveredToolNames, id: \.self) { toolName in
                                Label(toolName, systemImage: "wrench")
                                    .typography(Typography.body)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.surface.standard.base.ignoresSafeArea())
            .navigationTitle(Localized.Settings.Action.addMcpServer, style: Typography.titleXl)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localized.Common.Actions.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    toolbarAction
                }
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarAction: some View {
        switch phase {
        case .probing, .oauthAuthorizing, .connecting:
            ProgressView()
        case .done:
            Button(Localized.Common.Actions.add) { saveServer() }
        case .needsCredentials:
            Button(Localized.Ui.authorize) { continueWithCredentials() }
                .disabled(!isCredentialsValid)
        default:
            Button(Localized.Ui.connect) { startConnection() }
                .disabled(!isFormValid)
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        switch phase {
        case .idle, .needsCredentials:
            EmptyView()
        case .probing:
            Section {
                HStack(spacing: Spacing.n8) {
                    ProgressView()
                    Text(Localized.Mcp.Status.checking)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        case .oauthAuthorizing:
            Section {
                HStack(spacing: Spacing.n8) {
                    ProgressView()
                    Text(Localized.Auth.waiting)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        case .connecting:
            Section {
                HStack(spacing: Spacing.n8) {
                    ProgressView()
                    Text(Localized.Network.connecting)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        case .done:
            EmptyView()
        case .error(let message):
            Section {
                VStack(alignment: .leading, spacing: Spacing.n8) {
                    Label(
                        Localized.Errors.Connection.title,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(colors.text.standard.error)
                    .typography(Typography.titleXS)
                    Text(message)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
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
