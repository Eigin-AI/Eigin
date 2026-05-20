import Factory
import SafariServices
import SwiftData
import SwiftUI

/// Content for the provider connection sheet.
///
/// Handles OAuth or API key connection depending on the preset.
/// Calls back with the created provider.
struct ProviderConnectSheetContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService

    let preset: ProviderPreset
    let onComplete: (Provider) -> Void
    let onBack: () -> Void

    init(
        preset: ProviderPreset,
        onComplete: @escaping (Provider) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.preset = preset
        self.onComplete = onComplete
        self.onBack = onBack
        oauthService = preset.authMethod == .oAuthPKCE
            ? DefaultOAuthPKCEService(preset: preset)
            : nil
    }

    var body: some View {
        Group {
            if preset.authMethod == .oAuthPKCE {
                oauthFlow
            } else {
                apiKeyFlow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .sheet(isPresented: $showCreditsURL) {
            if let urlString = preset.apiKeyURL, let url = URL(string: urlString) {
                SafariView(url: url)
            }
        }
        .task {
            guard preset.authMethod == .oAuthPKCE, oauthKey == nil,
                  !isAuthenticating else { return }
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
                    Text(Localized.Onboarding.Provider.signingIn(preset.name))
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
                    Text(Localized.Onboarding.Provider.connectedTo(preset.name))
                        .typography(Typography.titleXS)

                    Text(Localized.Onboarding.Provider.creditsWarning)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                }

                AppButton(
                    Localized.Onboarding.Provider.addCreditsLabel(preset.name),
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
                VStack(spacing: Spacing.n16) {
                    Spacer()
                    ProgressView()
                    Text(Localized.Onboarding.Provider.signingIn(preset.name))
                        .typography(Typography.description)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else if let error = connectionError {
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

                    if let urlString = preset.apiKeyURL,
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

    // MARK: - Create Provider

    @State private var connectionError: ConnectionError?

    private func connectWithAPIKey() {
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

        Task {
            do {
                let client = LLMClientFactory.client(
                    baseURL: preset.baseURL, apiToken: token
                )
                let modelIDs = try await client.fetchModels()

                let provider = Provider(
                    name: preset.name,
                    baseURL: preset.baseURL
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
