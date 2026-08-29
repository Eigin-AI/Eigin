import Factory
import SwiftUI

struct AdvancedSettings: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Injected(\.voiceService) private var voiceService
    @Injected(\.languageManager) private var languageManager
    @AppStorage(StorageKey.logSinkToFile) private var logSinkToFile = true
    @AppStorage(StorageKey.logFileLevel) private var logFileLevel = AppLogger.LogLevel.info.rawValue
    @State private var logFileURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Settings.Section.advanced,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    let assets = voiceService.engineAssets(for: languageManager.currentLanguage)
                    if !assets.isEmpty {
                        speechEngineSection(assets: assets)
                    }

                    loggingSection
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { logFileURL = AppLogger.exportLog() }
    }

    // MARK: - Speech Engine

    private func speechEngineSection(assets: [any OnDemandAsset]) -> some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.speechEngine)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        if index > 0 {
                            Divider().padding(.horizontal, Spacing.n24)
                        }
                        EngineAssetRow(asset: asset)
                    }
                }
            }
        }
    }

    // MARK: - Logging

    private var loggingSection: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.logging)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    // Log to file toggle
                    HStack(spacing: Spacing.n16) {
                        Text(Localized.Settings.Logging.logToFile)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Spacer()
                        AppSwitch(isOn: logSinkToFile) { logSinkToFile.toggle() }
                    }
                    .padding(.horizontal, Spacing.n24)
                    .padding(.vertical, Spacing.n16)

                    // Description
                    Text(Localized.Settings.Logging.description)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.n24)
                        .padding(.bottom, Spacing.n16)

                    if logSinkToFile {
                        Divider().padding(.leading, Spacing.n24)

                        // Minimum level picker
                        AppOptionPicker(
                            title: Localized.Settings.Logging.minimumLevel,
                            options: AppLogger.LogLevel.allCases.map {
                                AppOption($0.displayName, value: $0.rawValue)
                            },
                            selection: logFileLevel
                        ) { logFileLevel = $0 }

                        if let url = logFileURL {
                            Divider().padding(.leading, Spacing.n24)

                            // Export log
                            ShareLink(item: url) {
                                HStack(spacing: Spacing.n16) {
                                    Text(Localized.Settings.Logging.exportLog)
                                        .typography(Typography.titleXS)
                                        .foregroundStyle(colors.text.standard.base)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                        .typography(Typography.miniLabel)
                                        .foregroundStyle(colors.text.standard.muted)
                                }
                                .padding(.horizontal, Spacing.n24)
                                .padding(.vertical, Spacing.n16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().padding(.leading, Spacing.n24)

                        // Clear log
                        Button(role: .destructive) {
                            AppLogger.clearLog()
                            logFileURL = nil
                        } label: {
                            HStack(spacing: Spacing.n16) {
                                Text(Localized.Settings.Logging.clearLog)
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.error)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.n24)
                            .padding(.vertical, Spacing.n16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}

// MARK: - Engine Asset Row

/// A disclosure row for a single downloadable engine asset.
/// Folding it out reveals the relevant action: download or delete.
struct EngineAssetRow: View {
    let asset: any OnDemandAsset
    @Environment(\.colors) private var colors
    @State private var showDownloadPrompt = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        AppDisclosure(asset.displayName, description: statusLabel, variant: .open) {
            actionContent
        }
        .alert("Delete \(asset.displayName)?", isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.delete, role: .destructive) { asset.delete() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(Localized.Model.removeWarning)
        }
        .appSheet(
            isPresented: $showDownloadPrompt,
            title: asset.displayName,
            detents: [.medium],
            fitsContent: true,
            showsDismissButton: false
        ) {
            AssetDownloadSheetContent(
                asset: asset,
                onAccept: { showDownloadPrompt = false },
                onDecline: { showDownloadPrompt = false }
            )
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        switch asset.state {
        case .ready:
            AppButton(Localized.Common.Actions.delete, variant: .destructive) {
                showDeleteConfirmation = true
            }
        case .notDownloaded, .failed:
            AppButton(Localized.Common.Actions.download) {
                showDownloadPrompt = true
            }
        case .downloading(let progress):
            HStack(spacing: Spacing.n12) {
                CircularProgressView(progress: progress)
                Text(Localized.Status.downloading)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
        case .downloaded, .compiling:
            HStack(spacing: Spacing.n12) {
                ProgressView()
                Text(Localized.Status.preparing)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
    }

    private var statusLabel: String? {
        switch asset.state {
        case .ready: Localized.Model.Status.installed
        case .downloading: Localized.Status.downloading
        case .downloaded, .compiling: Localized.Status.preparing
        case .notDownloaded, .failed: nil
        }
    }
}

#Preview {
    NavigationStack {
        AdvancedSettings()
    }
    .previewEnvironment()
}
