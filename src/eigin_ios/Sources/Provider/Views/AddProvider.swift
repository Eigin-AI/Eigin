import Factory
import SwiftData
import SwiftUI

struct AddProvider: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors
    @Injected(\.keychainService) private var keychainService

    let preset: ProviderPreset?

    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var connectionError: ConnectionError?

    @State private var fetchedModelIDs: [String] = []

    init(preset: ProviderPreset? = nil) {
        self.preset = preset
        if let preset {
            _name = State(initialValue: preset.name)
            _baseURL = State(initialValue: preset.baseURL)
        }
    }

    private var isLocal: Bool {
        ProviderPreset.isLocal(baseURL)
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && (isLocal || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        Form {
            if preset == nil {
                Section {
                    TextField(Localized.Provider.Add.nameField, text: $name)
                        .textContentType(.organizationName)
                        .autocorrectionDisabled()

                    TextField(Localized.Provider.Add.baseUrlField, text: $baseURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if isLocal {
                Section {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                        Text(preset?.helpText ?? "")
                    }
                }
            } else {
                Section {
                    SecureField(Localized.Common.Fields.apiKey, text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } footer: {
                    if let preset {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "info.circle")
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(preset.helpText)
                                if let urlString = preset.apiKeyURL,
                                   let url = URL(string: urlString)
                                {
                                    Link("Open \(preset.name)", destination: url)
                                }
                            }
                        }
                        .padding(.top, Spacing.sm)
                    } else {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "info.circle")
                            Text(Localized.Provider.Setup.Custom.apiRequirement)
                        }
                        .padding(.top, Spacing.sm)
                    }
                }
            }

            if let connectionError {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Label(connectionError.title, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(colors.destructive)
                            .typography(Typography.headline)
                        Text(connectionError.suggestion)
                            .typography(Typography.callout)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(
            preset?.name ?? Localized.Provider.Picker.customProvider,
            style: Typography.largeTitle
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isConnecting {
                    ProgressView()
                } else {
                    Button(Localized.Common.Actions.add) { isLocal ? connectLocal() : connect() }
                        .disabled(!isFormValid)
                }
            }
        }
    }

    private func connectLocal() {
        var models: [String] = []
        if FoundationModelClient.unavailableReason == nil {
            models.append("apple-foundation-model")
        }
        if GemmaModelManager.shared.state == .ready {
            models.append("gemma-4-e2b")
        }

        if models.isEmpty {
            connectionError = ConnectionError(
                title: Localized.Errors.notAvailable,
                suggestion: Localized.Errors.AppleIntelligence.notAvailable
            )
            Haptics.error()
            return
        }

        let provider = Provider(
            name: name.trimmingCharacters(in: .whitespaces),
            baseURL: "local://"
        )
        provider.availableModels = models
        modelContext.insert(provider)
        Haptics.success()
        dismiss()
    }

    private func connect() {
        isConnecting = true
        connectionError = nil

        Task {
            do {
                let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let client = LLMClientFactory.client(baseURL: trimmedURL, apiToken: apiKey)

                let modelIDs = try await client.fetchModels()

                if let firstModel = modelIDs.first {
                    try await client.validateAPIKey(model: firstModel)
                }

                fetchedModelIDs = modelIDs
                isConnecting = false
                Haptics.success()
                createProvider()
            } catch {
                connectionError = ConnectionError(from: error)
                isConnecting = false
                Haptics.error()
            }
        }
    }

    private func createProvider() {
        let provider = Provider(
            name: name.trimmingCharacters(in: .whitespaces),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
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
