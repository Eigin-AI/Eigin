import Factory
import SwiftData
import SwiftUI

/// Edit flow for an existing provider: API key re-validation and model refresh.
struct EditProvider: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Injected(\.keychainService) private var keychainService

    @Bindable var provider: Provider

    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var connectionError: ConnectionError?
    @State private var showRemoveConfirmation = false

    private var isLocal: Bool {
        ProviderPreset.isLocal(provider.baseURL)
    }

    private var isFormValid: Bool {
        isLocal || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Provider.Edit.title(provider.name),
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                },
                trailing: {
                    if !isLocal {
                        if isConnecting {
                            ProgressView()
                                .padding(.trailing, Spacing.n4)
                        } else {
                            AppActionButton(
                                icon: Image(systemName: "checkmark.circle"),
                                variant: .open,
                                size: .medium,
                                action: { reconnect() }
                            )
                            .disabled(!isFormValid)
                        }
                    }
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    infoCard
                    if !isLocal {
                        apiKeyCard
                    }
                    removeCard
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(Localized.Provider.Edit.title(provider.name), isPresented: $showRemoveConfirmation) {
            Button(Localized.Ui.remove, role: .destructive) { removeProvider() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(Localized.Provider.Edit.removeWarning)
        }
        .onAppear {
            if !isLocal {
                apiKey = keychainService
                    .read(key: keychainService.providerKey(for: provider.id)) ?? ""
            }
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                infoRow(label: Localized.Provider.Add.nameField, value: provider.name)
                Divider().padding(.leading, Spacing.n24)
                infoRow(label: Localized.Ui.url, value: provider.baseURL)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.n16) {
            Text(label)
                .typography(Typography.titleXS)
                .foregroundStyle(colors.text.standard.base)
            Spacer()
            Text(value)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
    }

    // MARK: - API Key Card

    private var apiKeyCard: some View {
        VStack(spacing: Spacing.n16) {
            AppTextInput(
                label: Localized.Common.Fields.apiKey,
                text: $apiKey,
                isError: connectionError != nil,
                errorMessage: connectionError?.title ?? "",
                isSecure: true
            )

            if let error = connectionError {
                Text(error.suggestion)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.n8)
            } else {
                HStack(alignment: .top, spacing: Spacing.n8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(colors.text.standard.muted)
                        .font(.system(size: 14))
                    Text(Localized.Provider.Edit.updateHintSave)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.n8)
            }
        }
    }

    // MARK: - Remove Card

    private var removeCard: some View {
        AppButton(Localized.Ui.remove, variant: .destructive) {
            showRemoveConfirmation = true
        }
    }

    // MARK: - Actions

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
                dismiss()
            } catch {
                connectionError = ConnectionError(from: error)
                isConnecting = false
            }
        }
    }

    private func removeProvider() {
        keychainService.delete(key: keychainService.providerKey(for: provider.id))
        modelContext.delete(provider)
        dismiss()
    }
}
