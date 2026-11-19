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
            nonisolated(unsafe) let taskRef = processingTask
            Task { @MainActor in handleTask(taskRef, container: container) }
        }
    }

    /// Schedules (or reschedules) the next background prompt run based on the proactivity level.
    /// Cancels any existing task first. Use for explicit proactivity changes and post-run
    /// rescheduling.
    @MainActor
    static func reschedule(for proactivity: ProactivityLevel, in context: ModelContext?) {
        scheduler.cancel(taskRequestWithIdentifier: taskIdentifier)

        guard let interval = proactivity.schedulingInterval, hasRemoteProvider(in: context) else {
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
    @MainActor
    static func scheduleIfNeeded(
        for proactivity: ProactivityLevel,
        in context: ModelContext
    ) async {
        guard proactivity.schedulingInterval != nil, hasRemoteProvider(in: context) else {
            scheduler.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }

        let pending = await scheduler.pendingTaskRequests()
        let alreadyScheduled = pending.contains { $0.identifier == taskIdentifier }

        if !alreadyScheduled {
            reschedule(for: proactivity, in: context)
        }
    }

    @MainActor
    private static func hasRemoteProvider(in context: ModelContext?) -> Bool {
        guard let context,
              let agent = (try? context.fetch(Agent.primaryDescriptor))?.primary
        else { return false }
        let providerID = agent.providerID
        let descriptor = FetchDescriptor<Provider>(predicate: #Predicate { $0.id == providerID })
        guard let provider = (try? context.fetch(descriptor))?.first else { return false }
        return !ProviderPreset.isLocal(provider.baseURL)
    }

    @MainActor
    private static func handleTask(_ bgTask: BGProcessingTask, container: ModelContainer) {
        start(
            installExpiration: { bgTask.expirationHandler = $0 },
            reschedule: {
                let context = ModelContext(container)
                let level = (try? context.fetch(Agent.primaryDescriptor))?.primary?
                    .proactivity ?? .balanced
                Self.reschedule(for: level, in: context)
            },
            complete: {
                bgTask.expirationHandler = nil
                bgTask.setTaskCompleted(success: $0)
            },
            run: { onResult in
                await BackgroundPromptService.runOpportunity(
                    container: container,
                    onResult: onResult
                )
            },
            deliver: { await deliver($0, container: container) }
        )
    }

    /// Binds one opportunity to OS expiration, result delivery, and completion.
    @MainActor @discardableResult
    static func start(
        installExpiration: (@escaping @Sendable () -> Void) -> Void,
        reschedule: @escaping @MainActor () -> Void,
        complete: @escaping @MainActor (Bool) -> Void,
        run: @escaping @MainActor (@escaping @MainActor (BackgroundPromptService.Result) async
            -> Void) async -> BackgroundPromptService.Opportunity,
        deliver: @escaping @MainActor (BackgroundPromptService.Result) async -> Delivery
    ) -> Task<Void, Never> {
        let lifecycle = BackgroundOpportunityLifecycle {
            reschedule()
            complete($0)
        }
        let workItem = Task { @MainActor in
            var deliverySucceeded = true
            let outcome = await run { result in
                if result.didNotify {
                    let delivery = await deliver(result)
                    AppLogger.info(
                        "Background delivery: \(public: delivery.label)",
                        category: .backgroundPrompt
                    )
                    deliverySucceeded = delivery.succeeded && deliverySucceeded
                }
            }
            AppLogger.info(
                "Background execution success: \(public: outcome.succeeded)",
                category: .backgroundPrompt
            )
            lifecycle.finish(success: !Task.isCancelled && outcome.succeeded && deliverySucceeded)
        }
        installExpiration {
            workItem.cancel()
            Task { @MainActor in lifecycle.finish(success: false) }
        }
        return workItem
    }

    enum Delivery {
        case silent
        case saved(FollowUpDeliveryStatus)
        case persistenceFailed(String)

        var label: String {
            switch self {
            case .silent: "silent"
            case .saved(let status): status.rawValue
            case .persistenceFailed: "persistence_failed"
            }
        }

        var succeeded: Bool {
            switch self {
            case .silent, .saved(.scheduled): true
            default: false
            }
        }
    }

    /// Persists and delivers one activity's notification through the shared follow-up path.
    @MainActor
    static func deliver(
        _ result: BackgroundPromptService.Result,
        container: ModelContainer,
        scheduler: (any FollowUpScheduling)? = nil
    ) async -> Delivery {
        guard result.didNotify, let agentID = result.agentID else { return .silent }
        return await sendNotification(
            container: container, title: result.notificationTitle ?? "New message",
            body: result.notificationBody ?? "", agentID: agentID,
            message: result.notificationBody ?? "", summary: result.summary,
            deliverAt: result.deliverAt, agentName: result.agentName, agentEmoji: result.agentEmoji,
            scheduler: scheduler
        )
    }

    @MainActor @discardableResult
    static func sendNotification(
        container: ModelContainer,
        title: String,
        body: String,
        agentID: UUID,
        message: String,
        summary: String? = nil,
        deliverAt: Date?,
        agentName: String? = nil,
        agentEmoji: String? = nil,
        scheduler: (any FollowUpScheduling)? = nil
    ) async -> Delivery {
        do {
            let result = try await (scheduler ?? DefaultFollowUpScheduler(container: container))
                .schedule(
                    title: title,
                    body: body,
                    message: message,
                    summary: summary,
                    deliverAt: deliverAt,
                    agentID: agentID,
                    agentName: agentName,
                    agentEmoji: agentEmoji,
                    spaceID: nil,
                    canPromptUser: false
                )
            return .saved(result.deliveryStatus)
        } catch {
            AppLogger.error(
                "Failed to schedule notification: \(private: error.localizedDescription)",
                category: .backgroundPrompt
            )
            return .persistenceFailed(error.localizedDescription)
        }
    }
}

/// Completes and reschedules an OS opportunity once, including expiration races.
@MainActor
final class BackgroundOpportunityLifecycle {
    private var finished = false
    private let complete: (Bool) -> Void

    init(complete: @escaping (Bool) -> Void) {
        self.complete = complete
    }

    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        complete(success)
    }
}
