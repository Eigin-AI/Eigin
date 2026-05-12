import Factory
import SwiftUI

struct AdvancedSettings: View {
    @Environment(\.colors) private var colors
    @Injected(\.voiceService) private var voiceService
    @Injected(\.languageManager) private var languageManager
    @AppStorage(StorageKey.logSinkToFile) private var logSinkToFile = false
    @AppStorage(StorageKey.logFileLevel) private var logFileLevel = AppLogger.LogLevel.info.rawValue
    @State private var logFileURL: URL?

    var body: some View {
        List {
            let assets = voiceService.engineAssets(for: languageManager.currentLanguage)
            if !assets.isEmpty {
                Section {
                    ForEach(assets, id: \.id) { asset in
                        EngineAssetRow(asset: asset)
                    }
                    .listRowBackground(colors.surface)
                } header: {
                    Text(Localized.Settings.speechEngine)
                        .typography(Typography.label)
                }
            }

            Section {
                Group {
                    Toggle(Localized.Settings.Logging.logToFile, isOn: $logSinkToFile)

                    Text(Localized.Settings.Logging.description)
                        .typography(Typography.caption)
                        .foregroundStyle(colors.textSecondary)

                    if logSinkToFile {
                        Picker("Minimum Level", selection: $logFileLevel) {
                            ForEach(AppLogger.LogLevel.allCases) { level in
                                Text(level.displayName).tag(level.rawValue)
                            }
                        }
                    }

                    if logSinkToFile {
                        if let url = logFileURL {
                            ShareLink(item: url) {
                                HStack(spacing: Spacing.sm) {
                                    SettingsIcon(systemName: "square.and.arrow.up", color: .blue)
                                    Text(Localized.Settings.Logging.exportLog)
                                        .typography(Typography.subheadline)
                                        .foregroundStyle(colors.textPrimary)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            AppLogger.clearLog()
                            logFileURL = nil
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                SettingsIcon(systemName: "trash", color: .red)
                                Text(Localized.Settings.Logging.clearLog)
                                    .typography(Typography.subheadline)
                            }
                        }
                    }
                }
                .listRowBackground(colors.surface)
            } header: {
                Text(Localized.Settings.logging)
                    .typography(Typography.label)
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(Localized.Settings.Section.advanced, style: Typography.largeTitle)
        .onAppear { logFileURL = AppLogger.exportLog() }
    }
}

// MARK: - Engine Asset Row

/// A row for a single downloadable engine asset with status badge and actions.
struct EngineAssetRow: View {
    let asset: any OnDemandAsset
    @Environment(\.colors) private var colors
    @State private var showDownloadPrompt = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(asset.displayName)
                    .typography(Typography.subheadline)
                    .foregroundStyle(colors.textPrimary)
            }
            Spacer()
            engineBadge
        }
        .alert("Delete \(asset.displayName)?", isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.delete, role: .destructive) { asset.delete() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(Localized.Model.removeWarning)
        }
        .sheet(isPresented: $showDownloadPrompt) {
            AssetDownloadPrompt(
                asset: asset,
                onAccept: { showDownloadPrompt = false },
                onDecline: { showDownloadPrompt = false }
            )
        }

        if asset.state == .ready {
            Button(Localized.Common.Actions.delete, role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    @ViewBuilder
    private var engineBadge: some View {
        switch asset.state {
        case .ready:
            Text(Localized.Model.Status.installed)
                .typography(Typography.caption)
                .foregroundStyle(.green)
        case .downloading(let progress):
            CircularProgressView(progress: progress)
        case .downloaded, .compiling:
            Text(Localized.Status.preparing)
                .typography(Typography.caption)
                .foregroundStyle(colors.textSecondary)
        case .notDownloaded, .failed:
            Button(Localized.Common.Actions.download) { showDownloadPrompt = true }
                .typography(Typography.caption)
        }
    }
}

#Preview {
    NavigationStack {
        AdvancedSettings()
    }
    .previewEnvironment()
}
