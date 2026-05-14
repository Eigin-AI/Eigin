import Factory
import SafariServices
import SwiftData
import SwiftUI

struct OAuthProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService

    let preset: ProviderPreset

    @State private var apiKey: String?
    @State private var isAuthenticating = false
    @State private var isFetchingModels = false
    @State private var connectionError: ConnectionError?
    @State private var wasCancelled = false
    @State private var showCreditsURL = false
    @State private var showManualFallback = false

    @State private var fetchedModelIDs: [String] = []

    private let oauthService: any OAuthPKCEService

    init(preset: ProviderPreset, oauthService: (any OAuthPKCEService)? = nil) {
        self.preset = preset
        self.oauthService = oauthService ?? DefaultOAuthPKCEService(preset: preset)
    }

    private var isAuthenticated: Bool {
        apiKey != nil
    }

    var body: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            if isAuthenticating {
                ProgressView()
                Text(Localized.Onboarding.Provider.signingIn(preset.name))
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.muted)
            } else if isAuthenticated {
                if let connectionError {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(colors.text.standard.error)

                    VStack(spacing: Spacing.n8) {
                        Text(connectionError.title)
                            .typography(Typography.titleXS)
                        Text(connectionError.suggestion)
                            .typography(Typography.note)
                            .foregroundStyle(colors.text.standard.muted)
                            .multilineTextAlignment(.center)
                    }

                    Button(Localized.Provider.tryAgain) { fetchModels() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(colors.accent)

                    VStack(spacing: Spacing.n8) {
                        Text(Localized.Onboarding.Provider.connectedTo(preset.name))
                            .typography(Typography.titleXS)

                        Text(
                            Localized.Provider.creditsWarning(preset.name)
                        )
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                    }

                    Button {
                        showCreditsURL = true
                    } label: {
                        Label(
                            Localized.Onboarding.Provider.addCreditsLabel(preset.name),
                            systemImage: "arrow.up.right"
                        )
                        .typography(Typography.note)
                    }
                }

            } else if wasCancelled {
                VStack(spacing: Spacing.n8) {
                    Text(Localized.Provider.signInDismissed)
                        .typography(Typography.titleXS)
                    Text(Localized.Provider.signInDismissedHint)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Spacing.n8) {
                    Button("Try Again") { startOAuth() }
                        .buttonStyle(.borderedProminent)

                    Button("Add API Key Manually") { showManualFallback = true }
                        .typography(Typography.note)
                }
            } else if let connectionError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.text.standard.error)

                VStack(spacing: Spacing.n8) {
                    Text(connectionError.title)
                        .typography(Typography.titleXS)
                    Text(connectionError.suggestion)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Spacing.n8) {
                    Button("Try Again") { startOAuth() }
                        .buttonStyle(.borderedProminent)

                    Button("Add API Key Manually") { showManualFallback = true }
                        .typography(Typography.note)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.n24)
        .frame(maxWidth: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(preset.name, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isFetchingModels {
                    ProgressView()
                } else if isAuthenticated, connectionError == nil {
                    Button("Add") { fetchModels() }
                }
            }
        }
        .sheet(isPresented: $showManualFallback) {
            NavigationStack {
                AddProvider(preset: preset)
            }
        }
        .sheet(isPresented: $showCreditsURL) {
            if let urlString = preset.apiKeyURL, let url = URL(string: urlString) {
                SafariView(url: url)
            }
        }
        .task {
            guard apiKey == nil, !isAuthenticating else { return }
            startOAuth()
        }
    }

    // MARK: - Actions

    private func startOAuth() {
        isAuthenticating = true
        connectionError = nil
        wasCancelled = false

        Task {
            do {
                let key = try await oauthService.authenticate()
                apiKey = key
                isAuthenticating = false
                Haptics.success()
            } catch let error as OAuthPKCEError where error == .userCancelled {
                isAuthenticating = false
                wasCancelled = true
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

    private func fetchModels() {
        guard let apiKey else { return }
        isFetchingModels = true
        connectionError = nil

        Task {
            do {
                let client = LLMClientFactory.client(baseURL: preset.baseURL, apiToken: apiKey)
                let modelIDs = try await client.fetchModels()

                fetchedModelIDs = modelIDs
                isFetchingModels = false
                Haptics.success()
                createProvider()
            } catch {
                connectionError = ConnectionError(from: error)
                isFetchingModels = false
                Haptics.error()
            }
        }
    }

    private func createProvider() {
        guard let apiKey else { return }

        let provider = Provider(
            name: preset.name,
            baseURL: preset.baseURL
        )
        provider.availableModels = fetchedModelIDs
        modelContext.insert(provider)

        keychainService.save(
            key: keychainService.providerKey(for: provider.id),
            value: apiKey
        )

        dismiss()
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
