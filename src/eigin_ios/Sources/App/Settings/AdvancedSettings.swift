import Factory
import SwiftUI

struct AdvancedSettings: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StorageKey.logSinkToFile) private var logSinkToFile = true
    @AppStorage(StorageKey.logFileLevel) private var logFileLevel = AppLogger.LogLevel.info.rawValue
    @State private var logFileURL: URL?

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                localAssetsSection

                loggingSection
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
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
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { logFileURL = AppLogger.exportLog() }
    }

    // MARK: - Local Assets

    /// Entry point to ``LocalAssetsView``: the single surface for managing
    /// every downloaded model and voice.
    private var localAssetsSection: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.Section.storage)

            AppCardSurface(padding: 0) {
                NavigationLink {
                    LocalAssetsView()
                        .hidesTabBar()
                } label: {
                    HStack(spacing: Spacing.n16) {
                        VStack(alignment: .leading, spacing: Spacing.n4) {
                            Text(Localized.Settings.LocalAssets.title)
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.text.standard.base)
                            Text(Localized.Settings.LocalAssets.subtitle)
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    .padding(.horizontal, Spacing.n24)
                    .padding(.vertical, Spacing.n16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

#Preview {
    NavigationStack {
        AdvancedSettings()
    }
    .previewEnvironment()
}
