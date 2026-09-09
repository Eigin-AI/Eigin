import Factory
import SafariServices
import SwiftData
import SwiftUI

/// Connecting one provider, whichever way it lets you in.
///
/// The three routes ask for different things and fail differently, but they
/// end the same: a header that says the connection is up, and one button back
/// to where you were. Nothing here reports success before it has been
/// checked. The name of an address-connected provider is offered rather than
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
    private enum Step {
        case start
        case working
        case failed
        case done
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService

    let mode: Mode
    /// The way in, carried straight from the group the row was picked from.
    let method: ProviderPreset.AuthMethod
    let onComplete: (Provider) -> Void
    let onBack: () -> Void

    init(
        mode: Mode,
        onComplete: @escaping (Provider) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.mode = mode
        method =
            switch mode {
            case .preset(_, let method): method
            case .custom: .apiKey
            }
        self.onComplete = onComplete
        self.onBack = onBack
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
        if preset != nil, method == .oAuthPKCE { return .signIn }
        if preset != nil { return .apiKey }
        return .address
    }

    @State private var step: Step = .start
    @State private var connectionError: ConnectionError?
    @State private var showCreditsURL = false
    /// Bumped whenever the user backs out of an attempt; in-flight tasks
    /// drop their results when stale, and never move the step again.
    @State private var connectAttempt = 0
    /// Models fetched by the check, held until Done commits the provider.
    @State private var createdModels: [String] = []
    @State private var pendingToken: String?
    @State private var pendingBaseURL: String?

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
            .padding(.bottom, Spacing.n32)
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

    private func startOAuth() {
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
            step = .done
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
        // on the models screen.
        provider.enabledModels = KnownModelCatalog.knownModels(in: createdModels)
        modelContext.insert(provider)

        keychainService.save(key: keychainService.providerKey(for: provider.id), value: token)

        onComplete(provider)
    }

    /// First worthwhile label from a URL's host — the integration sheet's
    /// root-label rule — falling back to a neutral word rather than empty.
    static func suggestedName(from urlString: String) -> String {
        let suggested = ConnectIntegrationSheet.suggestedName(from: urlString)
        return suggested.isEmpty ? "Provider" : suggested
    }
}

// MARK: - Safari View

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
