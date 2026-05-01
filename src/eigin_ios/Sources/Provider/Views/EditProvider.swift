import Factory
import SwiftData
import SwiftUI

/// Edit flow for an existing provider: API key re-validation and model refresh.
struct EditProvider: View {
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService

    @Bindable var provider: Provider
    @Binding var navigationPath: NavigationPath

    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var connectionError: ConnectionError?

    private var isLocal: Bool {
        ProviderPreset.isLocal(provider.baseURL)
    }

    private var isFormValid: Bool {
        isLocal || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(Localized.Provider.Add.nameField, value: provider.name)
                LabeledContent(Localized.Ui.url, value: provider.baseURL)
            }

            if !isLocal {
                Section {
                    SecureField(Localized.Common.Fields.apiKey, text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } footer: {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                        Text(Localized.Provider.Edit.updateHintSave)
                    }
                    .padding(.top, Spacing.sm)
                }
            }

            if let connectionError {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Label(connectionError.title, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(colors.destructive)
                            .font(Typography.headline)
                        Text(connectionError.suggestion)
                            .font(Typography.callout)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(Localized.Provider.Edit.title(provider.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isLocal {
                    EmptyView()
                } else if isConnecting {
                    ProgressView()
                } else {
                    Button(Localized.Common.Actions.save) { reconnect() }
                        .disabled(!isFormValid)
                }
            }
        }
        .onAppear {
            if !isLocal {
                apiKey = keychainService
                    .read(key: keychainService.providerKey(for: provider.id)) ?? ""
            }
        }
    }

    private func reconnect() {
        isConnecting = true
        connectionError = nil

        Task {
            do {
                let client = LLMClientFactory.client(
                    baseURL: provider.baseURL,
                    apiToken: apiKey
                )

                let modelIDs = try await client.fetchModels()

                if let firstModel = modelIDs.first {
                    try await client.validateAPIKey(model: firstModel)
                }

                provider.availableModels = modelIDs
                provider.updatedAt = .now

                keychainService.save(
                    key: keychainService.providerKey(for: provider.id),
                    value: apiKey
                )

                isConnecting = false
                navigationPath = NavigationPath()
            } catch {
                connectionError = ConnectionError(from: error)
                isConnecting = false
            }
        }
    }
}
