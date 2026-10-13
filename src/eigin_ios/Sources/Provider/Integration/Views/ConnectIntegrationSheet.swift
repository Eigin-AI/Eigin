import Factory
import SwiftData
import SwiftUI

/// What the connect sheet was asked to connect: a catalogue entry or an
/// address someone typed.
enum ConnectTarget {
    case type(IntegrationType)
    case address
}

/// Connecting one integration, whichever way it lets you in.
///
/// A built-in account signs in, a server you run wants a key, a mail account
/// wants half a dozen settings, and a server at an address has to be asked
/// what it needs before we can ask you for it. Only the first step differs:
/// waiting, failing and finishing are the same everywhere. Aula belongs to
/// the sign-in route — it is a browser sign-in rather than OAuth, but that is
/// a fact about the wiring, not about the step.
struct ConnectIntegrationSheet: View {
    let target: ConnectTarget
    /// The last step's button. A chat waiting on the answer says Continue.
    var doneLabel: String = Localized.Common.Actions.done
    var onConnected: () -> Void = {}
    var onCancelled: () -> Void = {}

    private enum Step {
        case start
        case working
        /// Only the address route reaches this: the server answered, and it
        /// wants credentials of its own rather than a sign-in.
        case credentials
        case failed
        case done
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.integrationOAuthService) private var oauthService
    @Injected(\.imapCredentialStore) private var imapCredentialStore
    @Injected(\.keychainService) private var keychainService
    @Injected(\.mcpOAuthService) private var mcpOAuthService

    @State private var step: Step = .start
    @State private var failure: String?

    /// Sign-in / preset-server state
    @State private var partialGrantWarning: String?

    // Mail-account state
    @State private var emailAddress = ""
    @State private var appPassword = ""
    @State private var imapHost = ""
    @State private var smtpHost = ""

    // Address state
    @State private var address = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var chosenName = ""
    @State private var detectedAuthType: MCPAuthType = .none
    @State private var oauthConfig: OAuthConfiguration?
    @State private var tempServerID = UUID()
    @State private var discoveredToolNames: [String] = []

    /// The Aula login sheet runs over the working step.
    @State private var showingAulaLogin = false
    /// True while the login sheet dismisses itself to hand the wait back;
    /// the dismiss handler must not read that as the user giving up.
    @State private var handedBackToWaiting = false
    /// Bumped when a connect attempt is abandoned (cancel, back, dismiss).
    /// In-flight tasks compare against it and drop their results if stale,
    /// so a late completion cannot overwrite a step the user has moved to.
    @State private var connectAttempt = 0

    private var type: IntegrationType? {
        if case .type(let t) = target { t } else { nil }
    }

    private var name: String {
        switch target {
        case .type(let t):
            t.displayName
        case .address:
            // Not named until it has answered: the sheet says what you are
            // doing, and the name is offered at the end where it can be
            // checked. Same in `Connect a provider`.
            step == .done && !chosenName.isEmpty
                ? chosenName
                : Localized.Integration.Connect.addressTitle
        }
    }

    var body: some View {
        AppFittedSheet(
            header: {
                AppSheetHeader(
                    title: step == .done ? Localized.Integration.Connect.connectedTitle : name,
                    description: step == .done ? nil : description,
                    onDismiss: {
                        discardAttempt()
                        onCancelled()
                    }
                )
            },
            primary: {
                flow
                    .padding(.horizontal, Spacing.n16)
            }
        )
        .alert(
            Localized.Ui.integrations,
            isPresented: Binding(
                get: { partialGrantWarning != nil },
                set: { if !$0 { partialGrantWarning = nil } }
            )
        ) {
            Button(Localized.Common.Actions.ok) {}
        } message: {
            Text(partialGrantWarning ?? "")
        }
        .sheet(
            isPresented: $showingAulaLogin,
            onDismiss: {
                if !handedBackToWaiting, step == .working {
                    step = .start
                }
                handedBackToWaiting = false
            }
        ) {
            if let type, case .webSession(let configFactory) = type.authKind {
                AddAulaAccount(
                    onConnected: {
                        step = .done
                    },
                    onVerifying: {
                        handedBackToWaiting = true
                        showingAulaLogin = false
                    },
                    onFailure: { message in
                        failure = message
                        step = .failed
                    },
                    config: configFactory()
                )
            }
        }
    }

    /// The one line under the title that says what this route asks of you.
    private var description: String {
        switch target {
        case .type(let type):
            switch type.authKind {
            case .oauth:
                Localized.Integration.Connect.Description.signIn(type.displayName)
            case .webSession:
                Localized.Integration.Connect.Description.browserSignIn(type.displayName)
            case .imap:
                Localized.Integration.Connect.Description.mailAccount
            case .platform:
                type.description
            }
        case .address:
            Localized.Integration.Connect.addressDescription
        }
    }

    @ViewBuilder
    private var flow: some View {
        switch step {
        case .start:
            startStep
        case .working:
            workingStep
        case .credentials:
            credentialsStep
        case .failed:
            failedStep
        case .done:
            doneStep
        }
    }

    // MARK: - Start

    @ViewBuilder
    private var startStep: some View {
        switch target {
        case .type(let type):
            switch type.authKind {
            case .oauth, .webSession:
                AppButton(
                    Localized.Integration.Connect.continueWith(type.displayName),
                    variant: .primary
                ) {
                    connectTyped(type)
                } trailing: {
                    Iconography.Functional.Arrow.upRight
                }

            case .imap:
                // The longest form in the app. Ports default to 993 and 587,
                // and most providers put both hosts under one domain, so only
                // what cannot be guessed is asked for.
                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    AppTextInput(
                        label: Localized.Integration.Connect.emailField,
                        text: $emailAddress
                    )
                    AppTextInput(
                        label: Localized.Integration.Connect.appPasswordField,
                        text: $appPassword,
                        isSecure: true
                    )

                    AppTextInput(label: Localized.Integration.Connect.imapField, text: $imapHost)
                    AppTextInput(
                        label: Localized.Integration.Connect.smtpField,
                        text: $smtpHost
                    )

                    AppButton(Localized.Ui.connect) { connectIMAP() }
                        .disabled(!isIMAPFormValid)
                }

            case .platform:
                // Platform types connect through ConnectPlatformSheet instead.
                EmptyView()
            }

        case .address:
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppTextInput(label: Localized.Integration.Connect.addressField, text: $address)
                AppButton(Localized.Ui.connect) { connectAddress() }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var isIMAPFormValid: Bool {
        !trimmed(emailAddress).isEmpty && !trimmed(appPassword).isEmpty
            && !trimmed(imapHost).isEmpty && !trimmed(smtpHost).isEmpty
    }

    // MARK: - Working

    private var workingStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppNotice(
                tone: .info,
                title: workingTitle,
                body: workingBody
            )

            AppButton(Localized.Common.Actions.cancel, variant: .secondary) {
                connectAttempt += 1
                step = .start
            }
        }
    }

    /// The header is the sheet's only close; without Save, a probed OAuth
    /// server's tokens would stay under the temporary id forever. The
    /// migration in `saveServer` deletes them anyway, so this is a no-op
    /// for a saved connection.
    private func discardAttempt() {
        connectAttempt += 1
        if detectedAuthType == .oauth {
            for suffix in MCPServer.keychainSuffixes {
                keychainService.delete(key: keychainService.mcpKey(
                    for: tempServerID,
                    suffix: suffix
                ))
            }
        }
    }

    private var workingTitle: String {
        switch target {
        case .type(let type):
            type.authKind.isBrowserSignIn
                ? Localized.Integration.Connect.Working.waitingTitle
                : Localized.Integration.Connect.Working.checkingTitle
        case .address:
            Localized.Integration.Connect.Working.checkingTitle
        }
    }

    private var workingBody: String {
        switch target {
        case .type(let type):
            type.authKind.isBrowserSignIn
                ? Localized.Integration.Connect.Working.waitingBody(type.displayName)
                : Localized.Integration.Connect.Working.checkingBody
        case .address:
            Localized.Integration.Connect.Working.checkingBody
        }
    }

    // MARK: - Credentials (address route only)

    private var isCredentialsFormValid: Bool {
        !trimmed(clientID).isEmpty
    }

    private var credentialsStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppNotice(
                tone: .info,
                title: Localized.Integration.Connect.Credentials.title,
                body: Localized.Integration.Connect.Credentials.body
            )

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppTextInput(label: Localized.Common.Fields.clientId, text: $clientID)
                AppTextInput(
                    label: Localized.Common.Fields.clientSecret,
                    text: $clientSecret,
                    isSecure: true
                )

                AppButton(Localized.Ui.connect) { continueWithCredentials() }
                    .disabled(!isCredentialsFormValid)
            }
        }
    }

    // MARK: - Failed

    private var failedStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppNotice(
                tone: .error,
                title: failedTitle,
                body: failure ?? failedFallbackBody
            )

            // The same two ways out of every failure: this again, or
            // something else entirely.
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Provider.tryAgain) { step = .start }
                AppButton(Localized.Integration.Connect.chooseAnother, variant: .secondary) {
                    discardAttempt()
                    onCancelled()
                }
            }
        }
    }

    private var failedTitle: String {
        switch target {
        case .type(let type):
            switch type.authKind {
            case .oauth, .webSession, .platform: Localized.Integration.Connect.Failed.signInTitle
            case .imap: Localized.Integration.Connect.Failed.mailTitle
            }
        case .address:
            Localized.Integration.Connect.Failed.addressTitle
        }
    }

    private var failedFallbackBody: String {
        switch target {
        case .type(let type):
            switch type.authKind {
            case .oauth, .webSession, .platform:
                Localized.Integration.Connect.Failed.signInBody(type.displayName)
            case .imap:
                Localized.Integration.Connect.Failed.mailBody
            }
        case .address:
            Localized.Integration.Connect.Failed.addressBody
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppIdentityHeader(
                name: name,
                kind: Localized.Integration.Connect.kindLabel,
                state: .connected,
                status: Localized.Integration.Connect.Status.connectedLabel,
                icon: markImage,
                letter: markImage == nil ? String(name.prefix(1)) : nil
            )

            // Only the address route needs this: everywhere else the name
            // came from the catalogue, not from a guess.
            if case .address = target {
                AppTextInput(label: Localized.Integration.Connect.nameField, text: $chosenName)
            }

            AppButton(doneLabel) {
                if case .address = target {
                    saveServer()
                }
                onConnected()
            }
        }
    }

    private var markImage: Image? {
        switch target {
        case .type(let type):
            type.brandImage
        case .address:
            Iconography.Functional.globe
        }
    }

    // MARK: - Connect: catalogue types

    private func connectTyped(_ type: IntegrationType) {
        switch type.authKind {
        case .oauth(let configFactory):
            authorizeOAuth(type, configFactory: configFactory)
        case .webSession(let configFactory):
            connectWebSession(type, configFactory: configFactory)
        case .imap:
            // The form itself is the start step; verification is below.
            connectIMAP()
        case .platform:
            // Platform types connect through ConnectPlatformSheet instead.
            break
        }
    }

    private func connectWebSession(
        _ type: IntegrationType,
        configFactory: @escaping @Sendable () -> PKCEOAuthConfig
    ) {
        let config = configFactory()
        // Same fail-fast as OAuth: without the client id, the login page
        // can't complete, which would read to the user as a silent hang.
        guard !config.clientID.isEmpty else {
            failure = IntegrationOAuthError.notConfigured(type.displayName)
                .localizedDescription
            step = .failed
            return
        }
        step = .working
        showingAulaLogin = true
    }

    private func authorizeOAuth(
        _ type: IntegrationType,
        configFactory: @escaping @Sendable () -> PKCEOAuthConfig
    ) {
        step = .working

        Task {
            do {
                let integrationID = UUID()
                let result = try await IntegrationConnect.authorizeOAuth(
                    oauthService: oauthService,
                    type: type,
                    config: configFactory(),
                    integrationID: integrationID,
                    labelFallback: type.displayName
                )

                // Reuse the id authorize() already stored tokens under — no
                // need to migrate keychain keys to a separately-minted id.
                let integration = Integration(
                    id: integrationID,
                    typeID: type.id,
                    accountLabel: result.accountLabel,
                    grantedCapabilities: result.grantedCapabilities.map(\.rawValue)
                )
                modelContext.insert(integration)

                let ungranted = type.providedCapabilities.subtracting(result.grantedCapabilities)
                if !ungranted.isEmpty {
                    partialGrantWarning = IntegrationCopy.partialGrant(
                        accountLabel: result.accountLabel,
                        ungranted: ungranted
                    )
                }

                Haptics.success()
                step = .done
            } catch IntegrationOAuthError.userCancelled {
                step = .start
            } catch {
                failure = error.localizedDescription
                Haptics.error()
                step = .failed
            }
        }
    }

    // MARK: - Connect: mail account

    private func connectIMAP() {
        step = .working

        let settings = IMAPAccountSettings(
            emailAddress: trimmed(emailAddress),
            imapHost: trimmed(imapHost),
            imapPort: IMAPAccountSettings.defaultIMAPPort,
            smtpHost: trimmed(smtpHost),
            smtpPort: IMAPAccountSettings.defaultSMTPPort,
            imapUsername: nil,
            smtpUsername: nil,
            password: appPassword
        )

        Task {
            do {
                try await IMAPConnectionVerifier.verify(settings)
                let integration = Integration(
                    typeID: BundledIntegrationType.imap.id,
                    accountLabel: settings.emailAddress,
                    grantedCapabilities: [Capability.email.rawValue]
                )
                imapCredentialStore.save(settings, for: integration.id)
                modelContext.insert(integration)
                Haptics.success()
                step = .done
            } catch {
                failure = error.localizedDescription
                Haptics.error()
                step = .failed
            }
        }
    }

    // MARK: - Connect: address (MCP)

    private func connectAddress() {
        step = .working
        discoveredToolNames = []
        tempServerID = UUID()
        oauthConfig = nil
        detectedAuthType = .none
        chosenName = Self.suggestedName(from: Self.normalizedAddress(address))
        connectAttempt += 1
        let attempt = connectAttempt

        Task {
            func isCurrent() -> Bool {
                attempt == connectAttempt
            }
            guard let endpoint = URL(string: Self.normalizedAddress(address)) else {
                guard isCurrent() else { return }
                failure = Localized.Integration.Connect.invalidAddress
                Haptics.error()
                step = .failed
                return
            }

            do {
                // The server has to be asked what it needs before we can ask
                // you for it.
                let config = try await mcpOAuthService.discoverOAuth(for: endpoint)
                if let config {
                    guard isCurrent() else { return }
                    oauthConfig = config
                    detectedAuthType = .oauth
                    if config.needsClientCredentials {
                        step = .credentials
                        return
                    }
                    try await authorizeAndConnect(config: config, endpoint: endpoint)
                } else {
                    try await connectAndDiscover(endpoint: endpoint, authProvider: NoAuthProvider())
                }
                guard isCurrent() else { return }
                step = .done
                Haptics.success()
            } catch MCPOAuthError.userCancelled {
                guard isCurrent() else { return }
                step = .start
            } catch {
                guard isCurrent() else { return }
                AppLogger.error(
                    "Connect by address failed for \(public: endpoint.diagnosticsAddress): \(public: error.localizedDescription)",
                    category: .mcp
                )
                failure = error.localizedDescription
                Haptics.error()
                step = .failed
            }
        }
    }

    private func continueWithCredentials() {
        guard var config = oauthConfig else { return }

        let secret = trimmed(clientSecret)
        config = config.withClientCredentials(
            clientID: trimmed(clientID),
            clientSecret: secret.isEmpty ? nil : secret
        )
        oauthConfig = config
        step = .working

        Task {
            guard let endpoint = URL(string: Self.normalizedAddress(address)) else {
                failure = Localized.Integration.Connect.invalidAddress
                step = .failed
                return
            }

            do {
                try await authorizeAndConnect(config: config, endpoint: endpoint)
                step = .done
                Haptics.success()
            } catch MCPOAuthError.userCancelled {
                step = .credentials
            } catch {
                AppLogger.error(
                    "Client-credentials connect failed for \(public: endpoint.diagnosticsAddress): \(public: error.localizedDescription)",
                    category: .mcp
                )
                failure = error.localizedDescription
                Haptics.error()
                step = .failed
            }
        }
    }

    /// Runs OAuth authorization then connects to verify.
    private func authorizeAndConnect(config: OAuthConfiguration, endpoint: URL) async throws {
        _ = try await mcpOAuthService.authorize(config: config, serverID: tempServerID)
        let authProvider = OAuthAuthProvider(oauthService: mcpOAuthService, serverID: tempServerID)
        try await connectAndDiscover(endpoint: endpoint, authProvider: authProvider)
    }

    /// Connects to the server, discovers tools, then disconnects the test
    /// connection — the real connection is established by
    /// ``MCPServerManager`` after saving.
    private func connectAndDiscover(endpoint: URL, authProvider: any MCPAuthProvider) async throws {
        let connection = MCPServerConnection(
            serverName: chosenName,
            endpoint: endpoint,
            authProvider: authProvider
        )
        try await connection.connect()
        let tools = await connection.tools()
        discoveredToolNames = tools.map(\.name)
        await connection.disconnect()
    }

    /// Marks the model with everything learned, and migrates keychain tokens
    /// from the temporary id to the real one.
    private func saveServer() {
        let normalized = Self.normalizedAddress(address)
        let server = MCPServer(
            name: chosenName.isEmpty ? Self.suggestedName(from: normalized) : chosenName,
            url: normalized,
            authType: detectedAuthType
        )
        server.cachedToolNames = discoveredToolNames

        if let config = oauthConfig {
            server.oauthClientID = config.clientID
            server.oauthAuthURL = config.authorizationEndpoint.absoluteString
            server.oauthTokenURL = config.tokenEndpoint.absoluteString
            server.oauthScopes = config.scopes?.joined(separator: " ")
        }

        modelContext.insert(server)

        if detectedAuthType == .oauth {
            for suffix in MCPServer.keychainSuffixes {
                let oldKey = keychainService.mcpKey(for: tempServerID, suffix: suffix)
                if let value = keychainService.read(key: oldKey) {
                    keychainService.save(
                        key: keychainService.mcpKey(for: server.id, suffix: suffix),
                        value: value
                    )
                    keychainService.delete(key: oldKey)
                }
            }
        }
    }

    // MARK: - Helpers

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An address that will parse: `https` assumed where the person left
    /// the scheme off, which is almost always.
    static func normalizedAddress(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("://") ? value : "https://\(value)"
    }

    /// First worthwhile label from a URL's host: the label before the
    /// public suffix — code.eigin.ai suggests Eigin, api.infercom.eu
    /// Infercom. A guess, offered for confirmation.
    static func suggestedName(from urlString: String) -> String {
        var host = urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map(String.init) ?? urlString
        if host.contains(":") {
            host = host.split(separator: ":").first.map(String.init) ?? host
        }

        let labels = host.split(separator: ".").map(String.init)
        guard let brand = labels.count >= 3 ? labels.suffix(2).first : labels.first else {
            return ""
        }
        guard let first = brand.first else { return "" }
        return first.uppercased() + brand.dropFirst()
    }
}

extension IntegrationAuthKind {
    /// Aula and OAuth both hand over to the browser; the person doing it sees
    /// one step.
    var isBrowserSignIn: Bool {
        switch self {
        case .oauth, .webSession: true
        case .imap, .platform: false
        }
    }
}

#Preview("Sign in") {
    ConnectIntegrationSheet(target: .type(BundledIntegrationType.google))
        .previewEnvironment()
}
