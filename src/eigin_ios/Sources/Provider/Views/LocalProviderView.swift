import SwiftData
import SwiftUI

struct LocalProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors

    let preset: ProviderPreset

    @State private var showStorageError = false
    @State private var isCreating = false
    @Bindable private var gemmaManager = GemmaModelManager.shared

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            modelStatusList

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isCreating {
                    ProgressView()
                } else {
                    Button("Add") { createProvider() }
                }
            }
        }
        .alert("Not Enough Storage", isPresented: $showStorageError) {
            Button("OK", role: .cancel) {}
        } message: {
            let size = Double(GemmaModelManager.estimatedSize) / 1_000_000_000
            Text(
                Localized.Model.storageRequirement(String(format: "%.1f", size))
            )
        }
    }

    // MARK: - Model Status List

    private var modelStatusList: some View {
        VStack(spacing: Spacing.lg) {
            appleModelRow
            Divider()
            gemmaModelRow
        }
        .padding(Spacing.lg)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var appleModelRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "apple.logo")
                .font(.system(size: 28))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(Localized.Model.appleFoundationModel)
                    .font(Typography.body)
                Text(appleStatusText)
                    .font(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            appleStatusIcon
        }
    }

    @ViewBuilder
    private var appleStatusIcon: some View {
        if FoundationModelClient.unavailableReason != nil {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(colors.destructive)
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(colors.accent)
        }
    }

    private var appleStatusText: String {
        if let reason = FoundationModelClient.unavailableReason {
            return reason
        }
        return "Ready to use"
    }

    private var gemmaModelRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "brain")
                .font(.system(size: 28))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(Localized.Model.gemma4e2b)
                    .font(Typography.body)
                Text(gemmaStatusText)
                    .font(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            gemmaStatusWidget
        }
    }

    @ViewBuilder
    private var gemmaStatusWidget: some View {
        switch gemmaManager.state {
        case .notDownloaded:
            Button("Download") { startGemmaDownload() }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
        case .downloading(let progress):
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text(verbatim: "\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(colors.textSecondary)
            }
        case .downloaded, .compiling:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(colors.accent)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(colors.destructive)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(colors.destructive)
            }
        }
    }

    private var gemmaStatusText: String {
        switch gemmaManager.state {
        case .notDownloaded:
            let size = Double(GemmaModelManager.estimatedSize) / 1_000_000_000
            return "~\(String(format: "%.1f", size)) GB download — runs on Neural Engine"
        case .downloading:
            return "Downloading..."
        case .downloaded, .compiling:
            return Localized.Status.preparing
        case .ready:
            return "Downloaded and ready"
        case .failed(let message):
            return message
        }
    }

    // MARK: - Actions

    private func startGemmaDownload() {
        let freeSpace = try? FileManager.default
            .attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64
        guard (freeSpace ?? 0) >= GemmaModelManager.estimatedSize else {
            showStorageError = true
            return
        }

        Task {
            await gemmaManager.download()
        }
    }

    private var gemmaIsReady: Bool {
        if case .ready = gemmaManager.state { return true }
        return false
    }

    private func createProvider() {
        if FoundationModelClient.unavailableReason != nil, !gemmaIsReady {
            return
        }

        isCreating = true

        let provider = Provider(
            name: preset.name,
            baseURL: preset.baseURL
        )

        var models: [String] = []
        if FoundationModelClient.unavailableReason == nil {
            models.append("apple-foundation-model")
        }
        if gemmaIsReady {
            models.append("gemma-4-e2b")
        }
        provider.availableModels = models

        modelContext.insert(provider)
        Haptics.success()
        dismiss()
    }
}
