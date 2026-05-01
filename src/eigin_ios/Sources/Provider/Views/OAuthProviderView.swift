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
        VStack(spacing: Spacing.xl) {
            Spacer()

            if isAuthenticating {
                ProgressView()
                Text(Localized.Onboarding.Provider.signingIn(preset.name))
                    .font(Typography.body)
                    .foregroundStyle(colors.textSecondary)
            } else if isAuthenticated {
                if let connectionError {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(colors.destructive)

                    VStack(spacing: Spacing.sm) {
                        Text(connectionError.title)
                            .font(Typography.headline)
                        Text(connectionError.suggestion)
                            .font(Typography.callout)
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(Localized.Provider.tryAgain) { fetchModels() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(colors.accent)

                    VStack(spacing: Spacing.sm) {
                        Text(Localized.Onboarding.Provider.connectedTo(preset.name))
                            .font(Typography.headline)

                        Text(
                            Localized.Provider.creditsWarning(preset.name)
                        )
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
                }

            } else if wasCancelled {
                VStack(spacing: Spacing.sm) {
                    Text(Localized.Provider.signInDismissed)
                        .font(Typography.headline)
                    Text(Localized.Provider.signInDismissedHint)
                        .font(Typography.callout)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Spacing.sm) {
                    Button("Try Again") { startOAuth() }
                        .buttonStyle(.borderedProminent)

                    Button("Add API Key Manually") { showManualFallback = true }
                        .font(Typography.callout)
                }
            } else if let connectionError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.destructive)

                VStack(spacing: Spacing.sm) {
                    Text(connectionError.title)
                        .font(Typography.headline)
                    Text(connectionError.suggestion)
                        .font(Typography.callout)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Spacing.sm) {
                    Button("Try Again") { startOAuth() }
                        .buttonStyle(.borderedProminent)

                    Button("Add API Key Manually") { showManualFallback = true }
                        .font(Typography.callout)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(preset.name)
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
