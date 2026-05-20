import Factory
import SafariServices
import SwiftData
import SwiftUI

/// Content for the provider connection sheet.
///
/// Handles OAuth, API key, or custom connection setup depending on `mode`.
/// Calls back with the created provider.
struct ProviderConnectSheetContent: View {
    enum Mode {
        case preset(ProviderPreset)
        case custom
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService

    let mode: Mode
    let onComplete: (Provider) -> Void
    let onBack: () -> Void

    init(
        mode: Mode,
        onComplete: @escaping (Provider) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.mode = mode
        self.onComplete = onComplete
        self.onBack = onBack
        oauthService = if case .preset(let preset) = mode, preset.authMethod == .oAuthPKCE {
            DefaultOAuthPKCEService(preset: preset)
        } else {
            nil
        }
    }

    private var preset: ProviderPreset? {
        if case .preset(let p) = mode { p } else { nil }
    }

    private var displayName: String {
        preset?.name ?? Localized.Provider.Picker.customProvider
    }

    var body: some View {
        Group {
            switch mode {
            case .preset(let preset):
                if preset.authMethod == .oAuthPKCE {
                    oauthFlow
                } else {
                    apiKeyFlow
                }
            case .custom:
                customFlow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .sheet(isPresented: $showCreditsURL) {
            if let urlString = preset?.apiKeyURL, let url = URL(string: urlString) {
                SafariView(url: url)
            }
        }
        .task {
            guard case .preset(let p) = mode, p.authMethod == .oAuthPKCE,
                  oauthKey == nil, !isAuthenticating
            else { return }
            startOAuth()
        }
    }

    // MARK: - OAuth Flow

    @State private var oauthKey: String?
    @State private var isAuthenticating = false
    @State private var showCreditsURL = false

    private let oauthService: (any OAuthPKCEService)?

    private var isOAuthDone: Bool {
        oauthKey != nil
    }

    private var oauthFlow: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            if isAuthenticating {
                VStack(spacing: Spacing.n16) {
                    ProgressView()
                    Text(Localized.Onboarding.Provider.signingIn(displayName))
                        .typography(Typography.description)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                }
            } else if let connectionError {
                VStack(spacing: Sizing.PageLayout.gap) {
                    errorContent(connectionError)

                    VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                        AppButton(Localized.Provider.tryAgain) { startOAuth() }
                        AppButton(
                            Localized.Provider.Setup.changeProvider,
                            variant: .secondary
                        ) { onBack() }
                    }
                }
            } else if isOAuthDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.accent)

                VStack(spacing: Spacing.n8) {
                    Text(Localized.Onboarding.Provider.connectedTo(displayName))
                        .typography(Typography.titleXS)

                    Text(Localized.Onboarding.Provider.creditsWarning)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                }

                AppButton(
                    Localized.Onboarding.Provider.addCreditsLabel(displayName),
                    variant: .secondary,
                    size: .medium
                ) {
                    showCreditsURL = true
                } trailing: {
                    Iconography.Functional.Arrow.upRight
                }
            } else {
                ProgressView()
            }

            Spacer()

            if isOAuthDone, connectionError == nil {
                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    AppButton(Localized.Common.Actions.continue) {
                        createProviderAndContinue()
                    }
                    AppButton(
                        Localized.Provider.Setup.changeProvider,
                        variant: .secondary
                    ) { onBack() }
                }
                .padding(.bottom, Spacing.n32)
            } else if connectionError == nil, !isAuthenticating {
                AppButton(
                    Localized.Provider.Setup.changeProvider,
                    variant: .secondary
                ) { onBack() }
                    .padding(.bottom, Spacing.n32)
            }
        }
        .padding(.horizontal, Spacing.n24)
    }

    private func startOAuth() {
        isAuthenticating = true
        connectionError = nil

        Task {
            do {
                let key = try await oauthService!.authenticate()
                oauthKey = key
                isAuthenticating = false
                Haptics.success()
            } catch let error as OAuthPKCEError where error == .userCancelled {
                isAuthenticating = false
                connectionError = ConnectionError(
                    title: Localized.Errors.Oauth.dismissedTitle,
                    suggestion: Localized.Onboarding.Provider.signInDismissedHint
                )
            } catch {
                connectionError = ConnectionError(
                    title: Localized.Errors.Connection.title,
                    suggestion: error.localizedDescription
                )
                isAuthenticating = false
                Haptics.error()
            }
        }
    }

    // MARK: - API Key Flow

    @State private var apiKey = ""
    @State private var isConnecting = false

    private var isAPIKeyValid: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var apiKeyFlow: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            if isConnecting {
                connectingState
            } else if let error = connectionError {
                errorState(error)
            } else {
                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    AppTextInput(
                        label: Localized.Common.Fields.apiKey,
                        text: $apiKey,
                        isSecure: true
                    )

                    AppButton(Localized.Ui.connect) {
                        connectWithAPIKey()
                    }
                    .disabled(!isAPIKeyValid)

                    if let urlString = preset?.apiKeyURL,
                       let url = URL(string: urlString)
                    {
                        Link("Get API Key", destination: url)
                            .typography(Typography.navTab)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.n24)
    }

    // MARK: - Custom Flow

    @State private var customName = ""
    @State private var customBaseURL = ""

    private var isCustomFormValid: Bool {
        !customName.trimmingCharacters(in: .whitespaces).isEmpty
            && !customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var customFlow: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            if isConnecting {
                connectingState
            } else if let error = connectionError {
                errorState(error)
            } else {
                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    AppTextInput(
                        label: Localized.Provider.Add.nameField,
                        text: $customName
                    )
                    AppTextInput(
                        label: Localized.Provider.Add.baseUrlField,
                        text: $customBaseURL
                    )
                    AppTextInput(
                        label: Localized.Common.Fields.apiKey,
                        text: $apiKey,
                        isSecure: true
                    )

                    AppButton(Localized.Ui.connect) {
                        connectCustom()
                    }
                    .disabled(!isCustomFormValid)
                }
            }
        }
        .padding(.horizontal, Spacing.n24)
    }

    // MARK: - Shared States

    private var connectingState: some View {
        VStack(spacing: Spacing.n16) {
            Spacer()
            ProgressView()
            Text(Localized.Onboarding.Provider.signingIn(displayName))
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private func errorState(_ error: ConnectionError) -> some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            errorContent(error)

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Provider.tryAgain) {
                    connectionError = nil
                }
                AppButton(
                    Localized.Provider.Setup.changeProvider,
                    variant: .secondary
                ) { onBack() }
            }
        }
    }

    // MARK: - Create Provider

    @State private var connectionError: ConnectionError?

    private func connectWithAPIKey() {
        connectionError = nil
        isConnecting = true
        createProviderAndContinue(apiToken: apiKey.trimmingCharacters(in: .whitespaces))
    }

    private func connectCustom() {
        connectionError = nil
        isConnecting = true
        createProviderAndContinue(apiToken: apiKey.trimmingCharacters(in: .whitespaces))
    }

    private func createProviderAndContinue(apiToken: String? = nil) {
        let token = apiToken ?? oauthKey ?? ""
        guard !token.isEmpty else {
            isConnecting = false
            return
        }

        let providerName: String
        let providerBaseURL: String
        switch mode {
        case .preset(let preset):
            providerName = preset.name
            providerBaseURL = preset.baseURL
        case .custom:
            providerName = customName.trimmingCharacters(in: .whitespaces)
            providerBaseURL = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Task {
            do {
                let client = LLMClientFactory.client(
                    baseURL: providerBaseURL, apiToken: token
                )
                let modelIDs = try await client.fetchModels()

                let provider = Provider(
                    name: providerName,
                    baseURL: providerBaseURL
                )
                provider.availableModels = modelIDs
                provider.enabledModels = [KnownModelCatalog.bestModel(from: modelIDs) ?? ""]
                    .filter { !$0.isEmpty }
                modelContext.insert(provider)

                keychainService.save(
                    key: keychainService.providerKey(for: provider.id),
                    value: token
                )

                onComplete(provider)
            } catch {
                AppLogger.error(
                    "Failed to fetch models for provider: \(public: error.localizedDescription)",
                    category: .onboarding
                )
                connectionError = ConnectionError(
                    title: Localized.Errors.Authentication.failed,
                    suggestion: Localized.Errors.Provider.invalidApiKey
                )
                isConnecting = false
            }
        }
    }

    // MARK: - Error Content

    private func errorContent(_ error: ConnectionError) -> some View {
        VStack(spacing: Spacing.n16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(colors.text.standard.error)

            VStack(spacing: Spacing.n8) {
                Text(error.title)
                    .typography(Typography.titleXS)
                Text(error.suggestion)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
                    .multilineTextAlignment(.center)
            }
        }
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
