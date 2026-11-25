#if DEBUG
import Factory
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct DevelopmentMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors

    private enum BackgroundRunAction: Equatable {
        case due
        case activity(BackgroundRunMode)

        var mode: BackgroundRunMode? {
            if case .activity(let mode) = self { return mode }
            return nil
        }
    }

    @State private var activeBackgroundRun: BackgroundRunAction?
    @State private var lastResults: [BackgroundPromptService.Result] = []
    @State private var backgroundStatus: String?
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
    @State private var showResetOnboardingConfirmation = false

    var body: some View {
        List {
            Section(Localized.Settings.backgroundPrompt) {
                backgroundRunButton(
                    Localized.Development.triggerInitiativeRun,
                    icon: "play.fill", color: .green, action: .activity(.preparation)
                )
                backgroundRunButton(
                    Localized.Development.triggerMaintenanceRun,
                    icon: "wrench.fill", color: .orange, action: .activity(.maintenance)
                )
                backgroundRunButton(
                    Localized.Development.triggerReflectionRun,
                    icon: "sparkles", color: .purple, action: .activity(.reflection)
                )
                backgroundRunButton(
                    Localized.Development.runDueBackgroundActivities,
                    icon: "play.circle", color: .green, action: .due
                )

                Button {
                    lastResults = []
                    backgroundStatus = nil
                    lastError = nil
                    if BackgroundPromptService.makeAllActivitiesDue() {
                        backgroundStatus = Localized.Development.backgroundActivitiesDue
                    } else {
                        lastError = Localized.Development.backgroundActivitiesBusy
                    }
                } label: {
                    Label(
                        Localized.Development.makeBackgroundActivitiesDue,
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .disabled(activeBackgroundRun != nil)

                if let backgroundStatus {
                    Text(backgroundStatus)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                }

                ForEach(lastResults, id: \.mode) { result in
                    if let mode = result.mode {
                        Text(mode.rawValue.capitalized).typography(Typography.titleXS)
                    }
                    if result.status == .completed {
                        resultView(result)
                    } else {
                        Text(result.reason ?? String(describing: result.status))
                            .typography(Typography.note)
                            .foregroundStyle(.red)
                    }
                }

                if let error = lastError {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "xmark.circle", color: .red)
                        Text(error)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section(Localized.Ui.notifications) {
                Button {
                    sendTestNotification()
                } label: {
                    HStack(spacing: Spacing.n8) {
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
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "bell", color: .blue)
                        Text(Localized.Development.requestNotificationPermission)
                    }
                }
            }

            Section("Transcripts") {
                if transcripts.isEmpty {
                    Text(Localized.Development.noTranscripts)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                } else {
                    ForEach(transcripts, id: \.timestamp) { transcript in
                        Button {
                            selectedTranscript = transcript
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(transcript.signal
                                        .hasPrefix("notify") ? "Notify" : "Silent")
                                        .font(Typography.miniLabel.font.bold())
                                        .foregroundStyle(transcript.signal
                                            .hasPrefix("notify") ? .green : .orange)
                                    Spacer()
                                    Text(RelativeTimestamp.string(for: transcript.timestamp))
                                        .typography(Typography.miniLabel)
                                        .foregroundStyle(colors.text.standard.muted)
                                }
                                Text(transcript.reason)
                                    .typography(Typography.miniLabel)
                                    .foregroundStyle(colors.text.standard.muted)
                                    .lineLimit(2)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        BackgroundPromptDebug.clear()
                        transcripts = []
                    } label: {
                        HStack(spacing: Spacing.n8) {
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
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "doc.text", color: .blue)
                        Text(Localized.Development.viewAppLog)
                    }
                }

                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: StorageKey.logDebugMode) },
                    set: {
                        UserDefaults.standard.set($0, forKey: StorageKey.logDebugMode)
                        SDKDiagnosticReceiver.updateOptions()
                    }
                )) {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "eye", color: .purple)
                        Text(Localized.Development.debugMode)
                    }
                }
            }

            Section(Localized.Development.Credits.title) {
                NavigationLink {
                    CreditsDebug()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "creditcard", color: .green)
                        Text(Localized.Development.Credits.title)
                    }
                }
            }

            Section("Firm FFI") {
                Button {
                    firmResult = runFirmSanityCheck()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "cylinder.split.1x2", color: .teal)
                        Text(Localized.Development.firmSanityCheck)
                    }
                }

                if let firmResult {
                    Text(firmResult)
                        .font(Typography.miniLabel.font.monospaced())
                        .foregroundStyle(colors.text.standard.muted)
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
                    HStack(spacing: Spacing.n8) {
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
                        HStack(spacing: Spacing.n8) {
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
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "square.and.arrow.down", color: .orange)
                        Text(Localized.Development.importData)
                    }
                }

                if importSuccess {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "checkmark.circle", color: .green)
                        Text(Localized.Development.importSuccessful)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(.green)
                    }
                }

                if let importExportError {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "xmark.circle", color: .red)
                        Text(importExportError)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Onboarding") {
                Button {
                    showResetOnboardingConfirmation = true
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "arrow.counterclockwise", color: .purple)
                        Text(Localized.Settings.reTriggerOnboarding)
                    }
                }
            }

            Section(Localized.Development.Section.localModel) {
                NavigationLink {
                    ModelStorageView()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "internaldrive", color: .gray)
                        Text(Localized.Development.modelStorage)
                    }
                }
            }

            Section(Localized.Development.Section.backgroundScheduler) {
                Button {
                    BackgroundPromptScheduler.reschedule(for: .balanced, in: modelContext)
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "clock.arrow.circlepath", color: .purple)
                        Text(Localized.Development.scheduleBalanced)
                    }
                }

                Button {
                    BackgroundPromptScheduler.reschedule(for: .proactive, in: modelContext)
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "clock.arrow.circlepath", color: .indigo)
                        Text(Localized.Development.scheduleProactive)
                    }
                }

                Button(role: .destructive) {
                    BackgroundPromptScheduler.reschedule(for: .reactive, in: modelContext)
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "xmark.circle", color: .red)
                        Text(Localized.Development.cancelScheduledTask)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(Localized.Settings.Section.development, style: Typography.titleXl)
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
                    // The import replaces FirmSource rows behind the knowledge
                    // service's back; its cached snapshot would serve deleted
                    // rows otherwise.
                    if let knowledge = Container.shared.knowledgeService()
                        as? DefaultKnowledgeService
                    {
                        knowledge.invalidateVisibleSourcesCache()
                    }
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
        .confirmationDialog(
            "Reset Onboarding?",
            isPresented: $showResetOnboardingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Onboarding", role: .destructive) {
                retriggerOnboarding()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This starts a new agent from scratch and force-quits the app. " +
                    "Your existing agent and chats are kept but you'll go through onboarding again."
            )
        }
    }

    @ViewBuilder
    private func resultView(_ result: BackgroundPromptService.Result) -> some View {
        if result.didNotify {
            VStack(alignment: .leading, spacing: Spacing.n4) {
                HStack(spacing: Spacing.n8) {
                    SettingsIcon(systemName: "bell.fill", color: .green)
                    Text(Localized.Development.agentChoseToNotify)
                        .typography(Typography.titleXS)
                }
                if let title = result.notificationTitle {
                    Text(Localized.Ui.titleLabel(title))
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
                if let body = result.notificationBody {
                    Text(body)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                        .lineLimit(5)
                }
                Text(Localized.Development.chatWillBeCreated)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
                    .italic()
            }
        } else {
            HStack(spacing: Spacing.n8) {
                SettingsIcon(systemName: "moon.zzz", color: .gray)
                Text(Localized.Development.agentChoseToStaySilent)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
    }

    private func backgroundRunButton(
        _ title: String, icon: String, color: Color, action: BackgroundRunAction
    ) -> some View {
        Button {
            runBackgroundPrompt(action)
        } label: {
            HStack(spacing: Spacing.n8) {
                SettingsIcon(systemName: icon, color: color)
                Text(title)
                Spacer()
                if activeBackgroundRun == action { ProgressView() }
            }
        }
        .disabled(activeBackgroundRun != nil)
    }

    private func runBackgroundPrompt(_ action: BackgroundRunAction) {
        activeBackgroundRun = action
        let mode = action.mode
        lastResults = []
        backgroundStatus = nil
        lastError = nil

        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        let work = Task { @MainActor in
            let container = modelContext.container
            let results = await BackgroundPromptService.runOpportunity(
                container: container, modeOverride: mode
            ) { result in
                var preview = result
                if mode != nil { preview.deliverAt = Date().addingTimeInterval(1) }
                let delivery = await BackgroundPromptScheduler.deliver(
                    preview,
                    container: container
                )
                if !delivery.succeeded { lastError = "Background delivery: \(delivery)" }
            }
            switch results {
            case .ran(let activities): lastResults = activities
            case .localProvider: backgroundStatus = Localized.Settings.Proactivity
                .cloudProviderRequired
            case .nothingDue: backgroundStatus = Localized.Development.noBackgroundActivitiesDue
            case .busy: lastError = Localized.Development.backgroundActivitiesBusy
            default: lastError = "Background run: \(results)"
            }
            transcripts = BackgroundPromptDebug.getTranscripts()
            activeBackgroundRun = nil
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
        bgTaskID = UIApplication.shared.beginBackgroundTask {
            work.cancel()
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
    }

    private func runFirmSanityCheck() -> String {
        typealias SDK = KnowledgeSDKConversion.SDK
        do {
            let schema = SDK.Source(
                id: "schema",
                path: "schema.firm",
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
                readOnly: true
            )
            let people = SDK.Source(
                id: "people",
                path: "people.firm",
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
                readOnly: false
            )
            let session = try SDK.Workspace(sources: [schema, people])

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
            let dsl = try session.generateEntityDsl(
                entity: newEntity,
                sourcePath: "person/charlie.firm"
            )
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
