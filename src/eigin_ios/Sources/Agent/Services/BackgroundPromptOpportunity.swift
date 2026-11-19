import Factory
import Foundation
import SwiftData

/// Eligibility, admission, and completion tracking for one OS or manual opportunity.
extension BackgroundPromptService {
    /// Where activities record transcripts when the caller doesn't supply one.
    private static var defaultSink: any BackgroundPromptTranscriptSink {
#if DEBUG
        DebugTranscriptSink()
#else
        NoOpTranscriptSink()
#endif
    }

    enum Opportunity {
        case ran([Result])
        case disabled, localProvider, nothingDue, busy, missingAgent, missingProvider
        case configurationError(String)

        var succeeded: Bool {
            switch self {
            case .ran(let results): results.allSatisfy { $0.status == .completed }
            case .disabled, .localProvider, .nothingDue: true
            default: false
            }
        }
    }

    /// Evaluates all cooldowns and delivers each completed result before waiting for siblings.
    static func runOpportunity(
        container: ModelContainer,
        modeOverride: BackgroundRunMode? = nil,
        model: (any ChatService)? = nil,
        coordinator: BackgroundActivityCoordinator = Container.shared
            .backgroundActivityCoordinator(),
        transcriptSink: any BackgroundPromptTranscriptSink = defaultSink,
        onResult: @escaping @MainActor (Result) async -> Void = { _ in }
    ) async -> Opportunity {
        let context = ModelContext(container)
        let agentID: UUID
        let providerID: UUID
        do {
            guard let agent = try context.fetch(Agent.primaryDescriptor).primary
            else { return .missingAgent }
            guard agent.proactivity.isBackgroundEnabled else { return .disabled }
            agentID = agent.id
            providerID = agent.providerID
            guard let provider = try context.fetch(FetchDescriptor<Provider>(
                predicate: #Predicate { $0.id == providerID }
            )).first else { return .missingProvider }
            guard !ProviderPreset.isLocal(provider.baseURL) else { return .localProvider }
        } catch { return .configurationError(error.localizedDescription) }
        let modes = modeOverride.map { [$0] } ?? eligibleModes(now: Date())
        guard !modes.isEmpty else { return .nothingDue }
        let results = await runActivities(
            modes: modes, limit: 3, coordinator: coordinator,
            execute: { mode in
                await execute(
                    container: container, agentID: agentID, providerID: providerID,
                    mode: mode, model: model, transcriptSink: transcriptSink
                )
            },
            onResult: onResult
        )
        return results.map(Opportunity.ran) ?? .busy
    }

    /// Commits completed cooldowns before optional result delivery; failures remain due.
    static func runActivities(
        modes: [BackgroundRunMode], limit: Int,
        coordinator: BackgroundActivityCoordinator = Container.shared
            .backgroundActivityCoordinator(),
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { Date() },
        execute: @escaping @MainActor @Sendable (BackgroundRunMode) async -> Result,
        onResult: @escaping @MainActor (Result) async -> Void = { _ in }
    ) async -> [Result]? {
        await coordinator.run(
            activities: modes, limit: limit,
            execute: { mode in
                var result = await execute(mode)
                result.mode = mode
                if result.status == .completed { defaults.set(now(), forKey: mode.lastRunKey) }
                return result
            },
            onResult: { _, result in await onResult(result) }
        )
    }

#if DEBUG
    /// Makes activities eligible for the next debug or OS opportunity without starting a run.
    @discardableResult
    static func makeAllActivitiesDue(
        defaults: UserDefaults = .standard,
        coordinator: BackgroundActivityCoordinator = Container.shared
            .backgroundActivityCoordinator()
    ) -> Bool {
        guard !coordinator.isRunning else { return false }
        for mode in BackgroundRunMode.allCases {
            defaults.removeObject(forKey: mode.lastRunKey)
        }
        return true
    }
#endif

    /// Returns independently due activities, ordered by relative overdue time.
    static func eligibleModes(
        now: Date, defaults: UserDefaults = .standard
    ) -> [BackgroundRunMode] {
        BackgroundRunMode.allCases.enumerated().compactMap { index, mode -> (
            BackgroundRunMode,
            Double,
            Int
        )? in
            let last = defaults.object(forKey: mode.lastRunKey) as? Date
            let elapsed = last.map { now.timeIntervalSince($0) } ?? mode.cooldownInterval
            guard elapsed >= mode.cooldownInterval else { return nil }
            return (mode, elapsed / mode.cooldownInterval, index)
        }.sorted { a, b in a.1 == b.1 ? a.2 < b.2 : a.1 > b.1 }.map(\.0)
    }
}
