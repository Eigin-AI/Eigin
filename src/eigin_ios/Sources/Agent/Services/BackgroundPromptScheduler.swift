import BackgroundTasks
import SwiftData
import UserNotifications

/// Abstraction over `BGTaskScheduler` for testability.
protocol BackgroundTaskScheduling: Sendable {
    func cancel(taskRequestWithIdentifier identifier: String)
    func submit(_ taskRequest: BGTaskRequest) throws
    func pendingTaskRequests() async -> [BGTaskRequest]
}

extension BGTaskScheduler: BackgroundTaskScheduling {}

/// Manages BGProcessingTask scheduling for background agent reviews.
enum BackgroundPromptScheduler {
    static let taskIdentifier = AppKeys.backgroundTaskIdentifier

    /// Injectable scheduler — defaults to `BGTaskScheduler.shared`.
    /// Override in tests with a `FakeBackgroundTaskScheduler`.
    nonisolated(unsafe) static var scheduler: BackgroundTaskScheduling = BGTaskScheduler.shared

    /// Registers the background task handler. Call once from `EiginApp.init()`.
    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleTask(processingTask, container: container)
        }
    }

    /// Schedules (or reschedules) the next background prompt run based on the proactivity level.
    /// Cancels any existing task first. Use for explicit proactivity changes and post-run
    /// rescheduling.
    static func reschedule(for proactivity: ProactivityLevel) {
        scheduler.cancel(taskRequestWithIdentifier: taskIdentifier)

        guard let interval = proactivity.schedulingInterval else {
            return
        }

        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try scheduler.submit(request)
            AppLogger.info(
                "Scheduled: \(public: proactivity.displayName) — \(public: Int(interval))s",
                category: .backgroundPrompt
            )
        } catch {
            AppLogger.error(
                "Failed to schedule: \(private: error.localizedDescription)",
                category: .backgroundPrompt
            )
        }
    }

    /// Schedules a background task only if one isn't already pending.
    /// Use this for app-launch / foreground transitions to avoid pushing the schedule forward.
    static func scheduleIfNeeded(for proactivity: ProactivityLevel) async {
        guard proactivity.schedulingInterval != nil else { return }

        let pending = await scheduler.pendingTaskRequests()
        let alreadyScheduled = pending.contains { $0.identifier == taskIdentifier }

        if !alreadyScheduled {
            reschedule(for: proactivity)
        }
    }

    private static func handleTask(_ bgTask: BGProcessingTask, container: ModelContainer) {
        // BGProcessingTask is not Sendable, so we use nonisolated(unsafe)
        // to cross isolation boundaries. This is safe because the BG task
        // handler owns the task's lifecycle.
        nonisolated(unsafe) let taskForRun = bgTask
        let workItem = Task { @Sendable in
            await performBackgroundRun(container: container, task: taskForRun)
        }

        let workItemRef = workItem
        nonisolated(unsafe) let taskRef = bgTask
        bgTask.expirationHandler = { @Sendable in
            workItemRef.cancel()
            reschedule(for: .balanced)
            taskRef.setTaskCompleted(success: false)
        }
    }

    private static func performBackgroundRun(
        container: ModelContainer,
        task: BGProcessingTask
    ) async {
        AppLogger.info("Background task fired", category: .backgroundPrompt)

        let result = await BackgroundPromptService.run(container: container)

        if result.didNotify, let agentID = result.agentID {
            await sendNotification(
                container: container,
                title: result.notificationTitle ?? "New message",
                body: result.notificationBody ?? "",
                agentID: agentID,
                message: result.notificationBody ?? "",
                summary: result.summary,
                deliverAt: result.deliverAt,
                agentName: result.agentName,
                agentEmoji: result.agentEmoji
            )
        }

        // Always reschedule so the chain never breaks.
        // Fall back to .balanced if the agent fetch fails.
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.bootstrapComplete },
            sortBy: [SortDescriptor(\Agent.updatedAt, order: .reverse)]
        )
        let proactivity: ProactivityLevel = if let agents = try? context.fetch(descriptor),
                                               let agent = agents.first
        {
            agent.proactivity
        } else {
            .balanced
        }
        reschedule(for: proactivity)

        task.setTaskCompleted(success: true)
    }

    static func sendNotification(
        container: ModelContainer,
        title: String,
        body: String,
        agentID: UUID,
        message: String,
        summary: String? = nil,
        deliverAt: Date?,
        agentName: String? = nil,
        agentEmoji: String? = nil
    ) async {
        let context = ModelContext(container)

        let initiativeRequest = AgentInitiativeRequest(
            agentID: agentID,
            message: message,
            title: title,
            summary: summary
        )
        context.insert(initiativeRequest)
        try? context.save()

        let requestID = initiativeRequest.id.uuidString

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "agentID": agentID.uuidString,
            "notificationTitle": title,
            "message": message,
            "initiativeRequestID": requestID,
        ]

        let finalContent: UNNotificationContent = if let name = agentName {
            await CommunicationNotificationContent.upgrade(
                content, agentName: name, agentEmoji: agentEmoji, agentID: agentID
            )
        } else {
            content
        }

        let trigger: UNNotificationTrigger?
        if let deliverAt, deliverAt > Date() {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: deliverAt
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = nil // Deliver immediately
        }

        let request = UNNotificationRequest(
            identifier: "backgroundprompt-\(UUID().uuidString)",
            content: finalContent,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLogger.error(
                "Failed to send notification: \(private: error.localizedDescription)",
                category: .backgroundPrompt
            )
        }
    }
}
