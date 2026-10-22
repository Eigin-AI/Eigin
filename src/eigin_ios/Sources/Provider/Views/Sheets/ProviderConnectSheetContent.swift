import Factory
import SafariServices
import SwiftData
import SwiftUI

/// Connecting one provider, whichever way it lets you in.
///
/// The three routes ask for different things and fail differently, but they
/// end the same: a header that says the connection is up, and one button back
/// to where you were. Nothing here reports success before it has been
/// checked, and nothing is saved until the user allows sharing with it
/// (App Store guideline 5.1.2). The name of an address-connected provider is offered rather than
/// asked for: the domain is a good enough guess, and the one moment it is
/// worth confirming is once the thing has actually answered.
struct ProviderConnectSheetContent: View {
    enum Mode {
        /// A preset and the way the person chose to connect it — a provider
        /// offering both genuinely appears in both groups of the select
        /// sheet, and the group they picked from is the way they want in.
        case preset(ProviderPreset, method: ProviderPreset.AuthMethod)
        case custom
    }

    /// How you got here.
    private enum Route {
        case signIn
        case apiKey
        case address
    }

    /// How far you have got. The steps are shared: only the start differs.
    /// Exposed so presenters can adjust sheet chrome per step: the setup copy
    /// in the header (how to get a key, where to add credits) stops being true
    /// once the connection is up, and its height crowds the connected UI on
    /// short screens — so presenters drop it via `onStepChange` at `.done`.
    enum Step: Equatable {
        case start
        case working
        case failed
        /// The check passed; asks before anything personal is sent.
        case consent(AIConsentContent.Recipient)
        case done

        /// The sheet title for this step, given the presenter's own.
        func sheetTitle(_ base: String) -> String {
            if case .consent(let recipient) = self { return recipient.title }
            return base
        }

        /// The sheet description for this step, given the presenter's own.
        func sheetDescription(_ base: String?) -> String? {
            switch self {
            case .consent(let recipient): recipient.description
            case .done: nil
            default: base
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService
    @Injected(\.chatGPTCredentialStore) private var chatGPTCredentialStore
    @Injected(\.aiConsentStore) private var consentStore

    let mode: Mode
    /// The way in, carried straight from the group the row was picked from.
    let method: ProviderPreset.AuthMethod
    let onComplete: (Provider) -> Void
    let onBack: () -> Void
    let onStepChange: ((Step) -> Void)?

    init(
        mode: Mode,
        onComplete: @escaping (Provider) -> Void,
        onBack: @escaping () -> Void,
        onStepChange: ((Step) -> Void)? = nil
    ) {
        self.mode = mode
        method =
            switch mode {
            case .preset(_, let method): method
            case .custom: .apiKey
            }
        self.onComplete = onComplete
        self.onBack = onBack
        self.onStepChange = onStepChange
        oauthService =
            if case .preset(let preset, _) = mode, method == .oAuthPKCE {
                DefaultOAuthPKCEService(preset: preset)
            } else {
                nil
            }
    }

    private var preset: ProviderPreset? {
        if case .preset(let p, _) = mode { p } else { nil }
    }

    private var route: Route {
        if preset != nil, method == .oAuthPKCE || method == .chatGPTSubscription { return .signIn }
        if preset != nil { return .apiKey }
        return .address
    }

    @State private var step: Step = .start {
        didSet { onStepChange?(step) }
    }

    @State private var connectionError: ConnectionError?
    @State private var showCreditsURL = false
    /// Bumped whenever the user backs out of an attempt; in-flight tasks
    /// drop their results when stale, and never move the step again.
    @State private var connectAttempt = 0
    /// Models fetched by the check, held until Done commits the provider.
    @State private var createdModels: [String] = []
    @State private var pendingToken: String?
    @State private var pendingBaseURL: String?
    /// ChatGPT sign-in: full credential held until Done commits the provider.
    @State private var pendingChatGPTCredential: ChatGPTCredential?
    /// One state for the consent screen — a two-state (flag + URL) sheet
    /// can present blank when SwiftUI snapshots the content before the URL
    /// lands. Dismissal cancels the in-flight flow.
    @State private var chatGPTAuth: ChatGPTAuthPresentation?
    /// Kept so dismissing the consent sheet cancels the in-flight flow.
    @State private var chatGPTAuthTask: Task<Void, Never>?

    // MARK: - Route state

    @State private var apiKey = ""
    @State private var address = ""
    /// The done step's editable name, seeded from the domain.
    @State private var chosenName = ""

    private var displayName: String {
        if route == .address {
            return chosenName.isEmpty
                ? Localized.Provider.Connect.addressTitle
                : chosenName
        }
        return preset?.name ?? Localized.Provider.Connect.addressTitle
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.surface.standard.base.ignoresSafeArea())
            .sheet(isPresented: $showCreditsURL) {
                if let urlString = preset?.apiKeyURL, let url = URL(string: urlString) {
                    SafariView(url: url)
                }
            }
            .sheet(item: $chatGPTAuth, onDismiss: {
                chatGPTAuthTask?.cancel()
            }) { auth in
                SafariView(url: auth.url)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .start:
            startStep
        case .working:
            workingStep
        case .failed:
            failedStep
        case .consent:
            consentStep
        case .done:
            doneStep
        }
    }

    // MARK: - Start

    @ViewBuilder
    private var startStep: some View {
        switch route {
        case .signIn:
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(
                    Localized.Provider.Setup.oauthConnect(preset?.name ?? ""),
                    variant: .primary
                ) {
                    startOAuth()
                } trailing: {
                    Iconography.Functional.Arrow.upRight
                }
            }
            .padding(.horizontal, Spacing.n24)

        case .apiKey:
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppTextInput(label: Localized.Common.Fields.apiKey, text: $apiKey, isSecure: true)

                AppButton(Localized.Ui.connect) { connectWithAPIKey() }
                    .disabled(!hasKey)

                if preset?.apiKeyURL != nil {
                    AppSubtleActionButton(
                        Localized.Provider.Connect.getApiKey,
                        icon: Iconography.Functional.Arrow.upRight,
                        size: .medium
                    ) {
                        showCreditsURL = true
                    }
                }
            }
            .padding(.horizontal, Spacing.n24)

        case .address:
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppTextInput(
                    label: Localized.Provider.Connect.addressField,
                    text: $address
                )
                AppTextInput(label: Localized.Common.Fields.apiKey, text: $apiKey, isSecure: true)

                AppButton(Localized.Ui.connect) { connectWithAPIKey() }
                    .disabled(!hasKey || address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Spacing.n24)
        }
    }

    private var hasKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Working

    /// A wait is something the screen is telling you, so it is a notice like
    /// any other. Nothing to press but the way out.
    private var workingStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppNotice(
                tone: .info,
                title: route == .signIn
                    ? Localized.Provider.Connect.Working.waitingTitle
                    : Localized.Provider.Connect.Working.checkingTitle,
                body: route == .signIn
                    ? Localized.Provider.Connect.Working.waitingBody(displayName)
                    : Localized.Provider.Connect.Working.checkingBody
            )

            AppButton(Localized.Common.Actions.cancel, variant: .secondary) {
                // Cancels any in-flight ChatGPT sign-in wait, which dismisses
                // the consent sheet through its own error path.
                chatGPTAuthTask?.cancel()
                connectAttempt += 1
                step = .start
            }
        }
        .padding(.horizontal, Spacing.n24)
    }

    // MARK: - Failed

    private var failedStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppNotice(
                tone: .error,
                title: connectionError?.title ?? Localized.Errors.Connection.title,
                body: connectionError?.suggestion ?? Localized.Errors.Provider.invalidApiKey
            )

            // The same two ways out of every failure: this again, or
            // something else entirely.
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Provider.tryAgain) { step = .start }
                AppButton(
                    Localized.Provider.Connect.chooseAnother,
                    variant: .secondary
                ) { onBack() }
            }
        }
        .padding(.horizontal, Spacing.n24)
    }

    // MARK: - Consent

    /// The last question before the provider is saved. Not now goes back to
    /// the list, with nothing saved.
    private var consentStep: some View {
        AIConsentContent(
            recipient: consentRecipient,
            onAllow: {
                if let baseURL = pendingBaseURL { consentStore.allow(baseURL: baseURL) }
                step = .done
            },
            onDecline: onBack
        )
        .padding(.horizontal, Spacing.n16)
    }

    private var consentRecipient: AIConsentContent.Recipient {
        .provider(name: displayName, privacyPolicyURL: preset?.privacyPolicyURL)
    }

    // MARK: - Done

    /// A header that says the connection is up, one fact worth reading, and
    /// one button back to where you were.
    private var doneStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppIdentityHeader(
                name: displayName,
                kind: Localized.Provider.AiScreen.kindLabel,
                state: .connected,
                status: Localized.Provider.AiScreen.Status.connected,
                icon: route == .address ? Iconography.Functional.globe : markImage,
                letter: markImage == nil ? String(displayName.prefix(1)) : nil
            )

            if route == .address {
                // Named from its domain, and editable while it is still
                // fresh: this is the one moment the guess is worth
                // confirming. The header above renames live.
                AppTextInput(label: Localized.Provider.Connect.nameField, text: $chosenName)
            }

            AppRowsGroup(
                footnote: Localized.Provider.Connect.doneFootnote,
                rows: [
                    AppRowSpec(
                        title: Localized.Provider.Connect.modelsRowTitle,
                        value: Localized.Provider.Connect.modelsAvailable("\(connectedModelCount)"),
                        accessory: .none
                    ),
                ]
            )

            AppButton(Localized.Common.Actions.done) {
                finish()
            }
            // AppSheet pads the content's bottom; extra padding only pushes
            // this button out of a short sheet.
        }
        .padding(.horizontal, Spacing.n24)
    }

    private var markImage: Image? {
        preset?.logo.map(Image.init(uiImage:))
    }

    private var connectedModelCount: Int {
        createdModels.count
    }

    // MARK: - OAuth

    @State private var oauthKey: String?
    @State private var isAuthenticating = false

    private let oauthService: (any OAuthPKCEService)?

    /// Created on demand — the sign-in service is cheap to build and the
    /// injected credential store isn't usable inside `init`.
    private var chatGPTService: ChatGPTSignInService? {
        if case .preset(let preset, _) = mode, preset.authMethod == .chatGPTSubscription {
            DefaultChatGPTSignInService(credentialStore: chatGPTCredentialStore)
        } else {
            nil
        }
    }

    private func startOAuth() {
        if chatGPTService != nil {
            startChatGPTSignIn()
            return
        }
        guard let oauthService, !isAuthenticating else { return }
        isAuthenticating = true
        connectionError = nil
        step = .working
        connectAttempt += 1
        let attempt = connectAttempt

        Task {
            func isCurrent() -> Bool {
                attempt == connectAttempt
            }
            defer { isAuthenticating = false }
            do {
                let key = try await oauthService.authenticate()
                guard isCurrent() else { return }
                oauthKey = key
                Haptics.success()
                await createProviderAndContinue(apiToken: key, attempt: attempt)
            } catch let error as OAuthPKCEError where error == .userCancelled {
                guard isCurrent() else { return }
                step = .start
            } catch {
                guard isCurrent() else { return }
                connectionError = ConnectionError(
                    title: Localized.Errors.Connection.title,
                    suggestion: error.localizedDescription
                )
                Haptics.error()
                step = .failed
            }
        }
    }

    // MARK: - ChatGPT sign-in (SIWC)

    /// Sign in with ChatGPT: the consent screen appears over the connect
    /// sheet, the loopback server on 127.0.0.1 receives the redirect, and the
    /// validated credential is verified against the Responses API before
    /// anything is saved.
    private func startChatGPTSignIn() {
        guard let chatGPTService, !isAuthenticating else { return }
        isAuthenticating = true
        connectionError = nil
        step = .working
        connectAttempt += 1
        let attempt = connectAttempt

        // Dismissing the consent sheet (swipe-down) cancels the wait — the
        // loopback server stops and the flow returns to the start step.
        chatGPTAuthTask = Task {
            func isCurrent() -> Bool {
                attempt == connectAttempt
            }
            defer {
                isAuthenticating = false
                chatGPTAuthTask = nil
            }
            do {
                let credential = try await chatGPTService.authenticate(
                    existingClientID: nil,
                    idTokenHint: nil
                ) { [self] url in
                    chatGPTAuth = ChatGPTAuthPresentation(url: url)
                }
                guard isCurrent() else { return }
                chatGPTAuthTask = nil
                chatGPTAuth = nil
                pendingChatGPTCredential = credential
                Haptics.success()
                await createProviderAndContinue(
                    apiToken: credential.accessToken,
                    attempt: attempt
                )
            } catch ChatGPTSubscriptionError.userCancelled, ChatGPTSubscriptionError.declined,
                is CancellationError
            {
                guard isCurrent() else { return }
                chatGPTAuthTask = nil
                chatGPTAuth = nil
                step = .start
            } catch {
                guard isCurrent() else { return }
                chatGPTAuthTask = nil
                chatGPTAuth = nil
                connectionError = ConnectionError(from: error)
                Haptics.error()
                step = .failed
            }
        }
    }

    // MARK: - Checks and creation

    /// The check is the connect: fetching the model list is the first thing
    /// the key has to survive, and nothing is saved until it does.
    private func connectWithAPIKey() {
        connectionError = nil
        step = .working
        let token = apiKey.trimmingCharacters(in: .whitespaces)
        connectAttempt += 1
        let attempt = connectAttempt
        Task {
            guard attempt == connectAttempt else { return }
            await createProviderAndContinue(apiToken: token, attempt: attempt)
        }
    }

    private func createProviderAndContinue(apiToken: String, attempt: Int) async {
        func isCurrent() -> Bool {
            attempt == connectAttempt
        }
        let speculativeBaseURL: String = switch mode {
        case .preset(let preset, _):
            preset.baseURL
        case .custom:
            // A bare host is assumed to be https.
            ConnectIntegrationSheet.normalizedAddress(address)
        }

        do {
            let client = LLMClientFactory.client(baseURL: speculativeBaseURL, apiToken: apiToken)
            let modelIDs = try await client.fetchModels()
            guard isCurrent() else { return }
            createdModels = modelIDs

            if case .custom = mode, chosenName.isEmpty {
                chosenName = Self.suggestedName(from: speculativeBaseURL)
            }

            // Held onto until the done step; the sheet commits on Done.
            pendingBaseURL = speculativeBaseURL
            pendingToken = apiToken
            step = .consent(consentRecipient)
            Haptics.success()
        } catch {
            guard isCurrent() else { return }
            AppLogger.error(
                "Failed to fetch models for provider: \(public: error.localizedDescription)",
                category: .onboarding
            )
            connectionError = ConnectionError(from: error)
            Haptics.error()
            step = .failed
        }
    }

    // MARK: - Completion

    private func finish() {
        guard let token = pendingToken, let baseURL = pendingBaseURL else {
            step = .start
            return
        }

        let providerName: String = switch mode {
        case .preset(let preset, _):
            preset.name
        case .custom:
            chosenName.isEmpty
                ? Self.suggestedName(from: baseURL)
                : chosenName
        }

        let provider = Provider(name: providerName, baseURL: baseURL)
        provider.availableModels = createdModels
        // Recommended and Other arrive on; unknown IDs start off and say why
        // on the models screen. A ChatGPT sign-in lists a small curated set
        // that may outrun the local catalogue, though — an empty result there
        // would leave a fresh connection unusable, so all models arrive on.
        let known = KnownModelCatalog.knownModels(in: createdModels)
        provider.enabledModels =
            (ProviderPreset.isChatGPTSubscription(baseURL) && known.isEmpty)
                ? createdModels
                : known

        if let credential = pendingChatGPTCredential {
            // Save before the provider becomes visible: a kill between insert
            // and save would leave a connection that looks signed in but is
            // not. The credential store is fast; Done can afford the await.
            Task {
                await chatGPTCredentialStore.save(credential, providerID: provider.id)
                modelContext.insert(provider)
                onComplete(provider)
            }
        } else {
            keychainService.save(
                key: keychainService.providerKey(for: provider.id),
                value: token
            )
            modelContext.insert(provider)
            onComplete(provider)
        }
    }

    /// First worthwhile label from a URL's host — the integration sheet's
    /// root-label rule — falling back to a neutral word rather than empty.
    static func suggestedName(from urlString: String) -> String {
        let suggested = ConnectIntegrationSheet.suggestedName(from: urlString)
        return suggested.isEmpty ? "Provider" : suggested
    }
}

// MARK: - Safari View
