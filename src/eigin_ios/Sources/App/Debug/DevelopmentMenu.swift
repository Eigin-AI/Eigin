#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct DevelopmentMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors

    @State private var isRunning = false
    @State private var lastResult: BackgroundPromptService.Result?
    @State private var lastError: String?
    @State private var transcripts: [BackgroundPromptTranscript] = []
    @State private var selectedTranscript: BackgroundPromptTranscript?
    @State private var firmResult: String?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var showImporter = false
    @State private var showImportConfirmation = false
    @State private var pendingImportURL: URL?
    @State private var importExportError: String?
    @State private var importSuccess = false

    var body: some View {
        List {
            Section(Localized.Settings.backgroundPrompt) {
                Button {
                    runBackgroundPrompt(mode: .initiative)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "play.fill", color: .green)
                        Text(Localized.Development.triggerInitiativeRun)
                        Spacer()
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)

                Button {
                    runBackgroundPrompt(mode: .maintenance)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "wrench.fill", color: .orange)
                        Text(Localized.Development.triggerMaintenanceRun)
                        Spacer()
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)

                if let result = lastResult {
                    resultView(result)
                }

                if let error = lastError {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "xmark.circle", color: .red)
                        Text(error)
                            .font(Typography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section(Localized.Ui.notifications) {
                Button {
                    sendTestNotification()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "bell.badge", color: .orange)
                        Text(Localized.Development.testNotification)
                    }
                }

                Button {
                    Task {
                        let granted = await NotificationPermission.requestIfNeeded()
                        lastError = granted ? nil : "Notification permission denied"
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "bell", color: .blue)
                        Text(Localized.Development.requestNotificationPermission)
                    }
                }
            }

            Section("Transcripts") {
                if transcripts.isEmpty {
                    Text(Localized.Development.noTranscripts)
                        .font(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                } else {
                    ForEach(transcripts, id: \.timestamp) { transcript in
                        Button {
                            selectedTranscript = transcript
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(transcript.signal
                                        .hasPrefix("notify") ? "Notify" : "Silent")
                                        .font(Typography.caption.bold())
                                        .foregroundStyle(transcript.signal
                                            .hasPrefix("notify") ? .green : .orange)
                                    Spacer()
                                    Text(RelativeTimestamp.string(for: transcript.timestamp))
                                        .font(Typography.caption)
                                        .foregroundStyle(colors.textSecondary)
                                }
                                Text(transcript.reason)
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        BackgroundPromptDebug.clear()
                        transcripts = []
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            SettingsIcon(systemName: "trash", color: .red)
                            Text(Localized.Development.clearTranscripts)
                        }
                    }
                    .disabled(transcripts.isEmpty)
                }
            }

            Section("App Log") {
                NavigationLink {
                    LogViewer()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "doc.text", color: .blue)
                        Text(Localized.Development.viewAppLog)
                    }
                }

                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: StorageKey.logDebugMode) },
                    set: { UserDefaults.standard.set($0, forKey: StorageKey.logDebugMode) }
                )) {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "eye", color: .purple)
                        Text(Localized.Development.debugMode)
                    }
                }
            }

            Section("Firm FFI") {
                Button {
                    firmResult = runFirmSanityCheck()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "cylinder.split.1x2", color: .teal)
                        Text(Localized.Development.firmSanityCheck)
                    }
                }

                if let firmResult {
                    Text(firmResult)
                        .font(Typography.caption.monospaced())
                        .foregroundStyle(colors.textSecondary)
                        .textSelection(.enabled)
                }
            }

            Section(Localized.Development.Section.dataBackup) {
                Button {
                    isExporting = true
                    importExportError = nil
                    do {
                        exportURL = try DataExportService.export(context: modelContext)
                    } catch {
                        importExportError = "Export failed: \(error.localizedDescription)"
                    }
                    isExporting = false
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "square.and.arrow.up", color: .blue)
                        Text(Localized.Development.exportAllData)
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        HStack(spacing: Spacing.sm) {
                            SettingsIcon(systemName: "doc.fill", color: .green)
                            Text(Localized.Development.shareExportFile)
                        }
                    }
                }

                Button(role: .destructive) {
                    showImporter = true
                    importExportError = nil
                    importSuccess = false
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "square.and.arrow.down", color: .orange)
                        Text(Localized.Development.importData)
                    }
                }

                if importSuccess {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "checkmark.circle", color: .green)
                        Text(Localized.Development.importSuccessful)
                            .font(Typography.caption)
                            .foregroundStyle(.green)
                    }
                }

                if let importExportError {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "xmark.circle", color: .red)
                        Text(importExportError)
                            .font(Typography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Onboarding") {
                Button {
                    retriggerOnboarding()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "arrow.counterclockwise", color: .purple)
                        Text(Localized.Settings.reTriggerOnboarding)
                    }
                }
            }

            Section(Localized.Development.Section.localModel) {
                NavigationLink {
                    ModelStorageView()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "internaldrive", color: .gray)
                        Text(Localized.Development.modelStorage)
                    }
                }
            }

            Section(Localized.Development.Section.backgroundScheduler) {
                Button {
                    BackgroundPromptScheduler.reschedule(for: .balanced)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "clock.arrow.circlepath", color: .purple)
                        Text(Localized.Development.scheduleBalanced)
                    }
                }

                Button {
                    BackgroundPromptScheduler.reschedule(for: .proactive)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "clock.arrow.circlepath", color: .indigo)
                        Text(Localized.Development.scheduleProactive)
                    }
                }

                Button(role: .destructive) {
                    BackgroundPromptScheduler.reschedule(for: .reactive)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "xmark.circle", color: .red)
                        Text(Localized.Development.cancelScheduledTask)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(Localized.Settings.Section.development)
        .onAppear {
            transcripts = BackgroundPromptDebug.getTranscripts()
        }
        .sheet(item: $selectedTranscript) { transcript in
            TranscriptDetail(transcript: transcript)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                showImportConfirmation = true
            case .failure(let error):
                importExportError = "File selection failed: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Replace All Data?",
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace All Data", role: .destructive) {
                guard let url = pendingImportURL else { return }
                do {
                    try DataExportService.importData(from: url, context: modelContext)
                    importSuccess = true
                } catch {
                    importExportError = "Import failed: \(error.localizedDescription)"
                }
                pendingImportURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text(
                Localized.Development.replaceAllDataMessage
            )
        }
    }

    @ViewBuilder
    private func resultView(_ result: BackgroundPromptService.Result) -> some View {
        if result.didNotify {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    SettingsIcon(systemName: "bell.fill", color: .green)
                    Text(Localized.Development.agentChoseToNotify)
                        .font(Typography.headline)
                }
                if let title = result.notificationTitle {
                    Text(Localized.Ui.titleLabel(title))
                        .font(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                if let body = result.notificationBody {
                    Text(body)
                        .font(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(5)
                }
                Text(Localized.Development.chatWillBeCreated)
                    .font(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
                    .italic()
            }
        } else {
            HStack(spacing: Spacing.sm) {
                SettingsIcon(systemName: "moon.zzz", color: .gray)
                Text(Localized.Development.agentChoseToStaySilent)
                    .font(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private func runBackgroundPrompt(mode: BackgroundRunMode) {
        isRunning = true
        lastResult = nil
        lastError = nil

        Task {
            var bgTaskID = UIBackgroundTaskIdentifier.invalid
            bgTaskID = UIApplication.shared.beginBackgroundTask {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }

            let container = modelContext.container
            let result = await BackgroundPromptService.run(container: container, modeOverride: mode)

            await MainActor.run {
                lastResult = result
                isRunning = false
                // If agent chose to notify, also fire the local notification
                // so we can test the full flow including deep linking.
                if result.didNotify, let agentID = result.agentID {
                    Task {
                        let container = modelContext.container
                        await BackgroundPromptScheduler.sendNotification(
                            container: container,
                            title: result.notificationTitle ?? "Background Prompt",
                            body: String((result.notificationBody ?? "").prefix(200)),
                            agentID: agentID,
                            message: result.notificationBody ?? "",
                            summary: result.summary,
                            deliverAt: Date().addingTimeInterval(1),
                            agentName: result.agentName,
                            agentEmoji: result.agentEmoji
                        )
                    }
                }

                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }

    private func runFirmSanityCheck() -> String {
        do {
            let session = FirmSession()

            // Load a schema
            try session.loadSource(
                content: """
                schema person {
                    field {
                        name = "name"
                        type = "string"
                        required = true
                    }
                    field {
                        name = "age"
                        type = "integer"
                        required = false
                    }
                }
                """,
                path: "schema.firm"
            )

            // Load entities
            try session.loadSource(
                content: """
                person alice {
                    name = "Alice"
                    age = 30
                }

                person bob {
                    name = "Bob"
                    age = 25
                }
                """,
                path: "people.firm"
            )

            // Build
            try session.build()

            // Query
            let result = try session.query(queryString: "from person | where age > 26")
            guard case .entities(let entities) = result else {
                return "Unexpected: got aggregation"
            }

            // Read fields from the result
            var lines = ["Query returned \(entities.count) entity:"]
            for entity in entities {
                lines.append("  \(entity.entityType).\(entity.id)")
                for field in entity.fields {
                    switch field.value {
                    case .string(let v): lines.append("    \(field.name) = \"\(v)\"")
                    case .integer(let v): lines.append("    \(field.name) = \(v)")
                    case .boolean(let v): lines.append("    \(field.name) = \(v)")
                    default: lines.append("    \(field.name) = (other)")
                    }
                }
            }

            // Generate DSL from a new entity
            let newEntity = FirmEntity(
                id: "person.charlie",
                entityType: "person",
                fields: [
                    FirmField(name: "name", value: .string(value: "Charlie")),
                    FirmField(name: "age", value: .integer(value: 35)),
                ]
            )
            let dsl = try session.generateEntityDsl(entity: newEntity)
            lines.append("\nGenerated DSL:")
            lines.append(dsl)

            return lines.joined(separator: "\n")
        } catch {
            return "Error: \(error)"
        }
    }

    private func sendTestNotification() {
        Task {
            let container = modelContext.container
            await BackgroundPromptScheduler.sendNotification(
                container: container,
                title: "Test Notification",
                body: "This is a test notification from the development menu.",
                agentID: UUID(),
                message: "This is a test notification from the development menu.",
                deliverAt: Date().addingTimeInterval(1),
                agentName: "Test Agent",
                agentEmoji: "🤖"
            )
        }
    }

    private func retriggerOnboarding() {
        do {
            let descriptor = FetchDescriptor<Agent>()
            let agents = try modelContext.fetch(descriptor)
            for agent in agents {
                agent.bootstrapComplete = false
            }
            try modelContext.save()

            UserDefaults.standard.set(
                OnboardingStep.welcome.rawValue,
                forKey: StorageKey.onboardingStep
            )
            UserDefaults.standard.set(false, forKey: StorageKey.onboardingComplete)

            // This force-quits the app to reload the root view properly,
            // as modifying AppStorage doesn't cleanly pop navigation stacks.
            exit(0)
        } catch {
            importExportError = "Failed to reset onboarding: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        DevelopmentMenu()
    }
    .previewEnvironment()
}
#endif
