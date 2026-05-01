import Factory
import SafariServices
import SwiftData
import SwiftUI

/// Handles provider connection during onboarding — OAuth or API key depending on preset.
/// This is a standalone screen in the linear onboarding flow, not pushed inside a NavigationStack.
struct OnboardingProviderConnect: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService

    let preset: ProviderPreset
    let onComplete: (Provider) -> Void
    var onBack: (() -> Void)?

    init(
        preset: ProviderPreset,
        onComplete: @escaping (Provider) -> Void,
        onBack: (() -> Void)? = nil
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
        .background(colors.background.ignoresSafeArea())
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
        VStack(spacing: Spacing.xl) {
            Spacer()

            if isAuthenticating {
                ProgressView()
                Text(Localized.Onboarding.Provider.signingIn(preset.name))
                    .font(Typography.body)
                    .foregroundStyle(colors.textSecondary)
            } else if let connectionError {
                errorContent(connectionError) {
                    startOAuth()
                }
            } else if isOAuthDone {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.accent)

                VStack(spacing: Spacing.sm) {
                    Text(Localized.Onboarding.Provider.connectedTo(preset.name))
                        .font(Typography.headline)

                    Text(Localized.Onboarding.Provider.creditsWarning)
                        .font(Typography.callout)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showCreditsURL = true
                } label: {
                    Label(
                        Localized.Onboarding.Provider.addCreditsLabel(preset.name),
                        systemImage: "arrow.up.right"
                    )
                    .font(Typography.callout)
                }
            } else {
                ProgressView()
            }

            Spacer()

            if isOAuthDone, connectionError == nil {
                VStack(spacing: Spacing.md) {
                    Button { createProviderAndContinue() } label: {
                        Text(Localized.Common.Actions.continue)
                            .font(Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(colors.accent)

                    if let onBack {
                        Button("Change Provider") { onBack() }
                            .font(Typography.callout)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                .padding(.bottom, Spacing.xl)
            } else if let onBack, !isAuthenticating {
                Button("Change Provider") { onBack() }
                    .font(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.bottom, Spacing.xl)
            }
        }
        .padding(.horizontal, Spacing.lg)
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

    private var isAPIKeyValid: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var apiKeyFlow: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.sm) {
                Text(preset.name)
                    .font(Typography.largeTitle)

                Text(preset.helpText)
                    .font(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)

                if let urlString = preset.apiKeyURL,
                   let url = URL(string: urlString)
                {
                    Link("Get API Key", destination: url)
                        .font(Typography.callout)
                }
            }

            SecureField(Localized.Common.Fields.apiKey, text: $apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .padding(Spacing.md)
                .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))

            Button(Localized.Ui.connect) {
                createProviderAndContinue(apiToken: apiKey.trimmingCharacters(in: .whitespaces))
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.accent)
            .disabled(!isAPIKeyValid)

            Spacer()

            if let onBack {
                Button("Change Provider") { onBack() }
                    .font(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.bottom, Spacing.xl)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Create Provider

    @State private var connectionError: ConnectionError?

    private func createProviderAndContinue(apiToken: String? = nil) {
        let token = apiToken ?? oauthKey ?? ""
        guard !token.isEmpty else { return }

        let provider = Provider(
            name: preset.name,
            baseURL: preset.baseURL
        )
        modelContext.insert(provider)

        keychainService.save(
            key: keychainService.providerKey(for: provider.id),
            value: token
        )

        Task {
            do {
                let client = LLMClientFactory.client(
                    baseURL: provider.baseURL, apiToken: token
                )
                let modelIDs = try await client.fetchModels()
                provider.availableModels = modelIDs
                provider.enabledModels = [KnownModelCatalog.bestModel(from: modelIDs) ?? ""]
                    .filter { !$0.isEmpty }
            } catch {
                AppLogger.error(
                    "Failed to fetch models for provider: \(public: error.localizedDescription)",
                    category: .onboarding
                )
            }
            onComplete(provider)
        }
    }

    // MARK: - Error Content

    private func errorContent(
        _ error: ConnectionError,
        retryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(colors.destructive)

            Text(error.title)
                .font(Typography.headline)
            Text(error.suggestion)
                .font(Typography.callout)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)

            Button(Localized.Provider.tryAgain) { retryAction() }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
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
