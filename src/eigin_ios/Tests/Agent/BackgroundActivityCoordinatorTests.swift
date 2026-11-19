@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Background activity execution")
@MainActor
struct BackgroundActivityCoordinatorTests {
    @Test func eligibilityUsesIndependentCompletionCooldowns() throws {
        let suite = "background-eligibility-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 200_000)
        #expect(BackgroundPromptService.eligibleModes(now: now, defaults: defaults) == [
            .preparation,
            .maintenance,
            .reflection,
        ])
        defaults.set(now, forKey: BackgroundRunMode.reflection.lastRunKey)
        defaults.set(
            now.addingTimeInterval(-6 * 3600 + 1),
            forKey: BackgroundRunMode.preparation.lastRunKey
        )
        defaults.set(
            now.addingTimeInterval(-2 * 86400),
            forKey: BackgroundRunMode.maintenance.lastRunKey
        )
        #expect(BackgroundPromptService
            .eligibleModes(now: now, defaults: defaults) == [.maintenance])
        defaults.set(
            now.addingTimeInterval(-6 * 3600),
            forKey: BackgroundRunMode.preparation.lastRunKey
        )
        #expect(BackgroundPromptService.eligibleModes(now: now, defaults: defaults) == [
            .preparation,
            .maintenance,
        ])
        defaults.set(now, forKey: BackgroundRunMode.maintenance.lastRunKey)
        #expect(BackgroundPromptService
            .eligibleModes(now: now, defaults: defaults) == [.preparation])
        defaults.set(now, forKey: BackgroundRunMode.preparation.lastRunKey)
        #expect(BackgroundPromptService.eligibleModes(now: now, defaults: defaults).isEmpty)
    }

#if DEBUG
    @Test func makingActivitiesDueClearsCooldownsOnlyWhileIdle() async throws {
        let suite = "background-debug-due-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let coordinator = BackgroundActivityCoordinator()
        for mode in BackgroundRunMode.allCases {
            defaults.set(now, forKey: mode.lastRunKey)
        }
        _ = await coordinator.run(activities: [0], limit: 1) { _ in
            #expect(!BackgroundPromptService.makeAllActivitiesDue(
                defaults: defaults,
                coordinator: coordinator
            ))
            #expect(BackgroundPromptService.eligibleModes(now: now, defaults: defaults).isEmpty)
        } onResult: { _, _ in }
        #expect(BackgroundPromptService.makeAllActivitiesDue(
            defaults: defaults,
            coordinator: coordinator
        ))
        #expect(BackgroundPromptService
            .eligibleModes(now: now, defaults: defaults) == BackgroundRunMode.allCases)
    }
#endif

    @Test func reactiveAgentDoesNotStartAnOpportunity() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Test", baseURL: "https://model.invalid")
        let agent = Agent(name: "Wren", providerID: provider.id, model: "test")
        agent.proactivity = .reactive
        container.mainContext.insert(provider)
        container.mainContext.insert(agent)
        try container.mainContext.save()
        var delivered = false
        let results = await BackgroundPromptService.runOpportunity(container: container) { _ in
            delivered = true
        }
        if case .disabled = results {}
        else { Issue.record("Reactive opportunity should be disabled") }
        #expect(!delivered)
    }

    @Test(arguments: [nil, BackgroundRunMode.reflection])
    func localProviderNeverStartsBackgroundWork(mode: BackgroundRunMode?) async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "On Device", baseURL: "local://")
        let agent = Agent(name: "Wren", providerID: provider.id, model: "gemma-4-e2b")
        agent.proactivity = .proactive
        container.mainContext.insert(provider)
        container.mainContext.insert(agent)
        try container.mainContext.save()
        let model = FakeChatService()
        let result = await BackgroundPromptService.runOpportunity(
            container: container, modeOverride: mode, model: model
        ) { _ in Issue.record("Expected no background activity result") }
        if case .localProvider = result {} else { Issue.record("Expected the local provider skip") }
        #expect(model.capturedEventMessages.isEmpty)
    }

    @Test func remoteActivitiesOverlapWithLimitOfThree() async {
        let coordinator = BackgroundActivityCoordinator()
        var started: [Int] = []
        var released: Set<Int> = []
        let work = Task { @MainActor in
            await coordinator.run(activities: [0, 1, 2, 3], limit: 3) { id in
                started.append(id)
                while !released.contains(id), !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                return id
            } onResult: { _, _ in }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while started.count < 3, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(Set(started) == [0, 1, 2])
        released.insert(0)
        while started.count < 4, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(started.last == 3)
        released = [0, 1, 2, 3]
        #expect(await Set(work.value ?? []) == [0, 1, 2, 3])
    }

    @Test func busyOpportunitiesCannotStartDuringAnActiveRun() async {
        let coordinator = BackgroundActivityCoordinator()
        var active = 0
        var order: [Int] = []
        let results = await coordinator.run(activities: [0, 1, 2], limit: 1) { id in
            active += 1
            #expect(active == 1)
            let duplicate = await coordinator.run(
                activities: [99],
                limit: 3,
                execute: { $0 },
                onResult: { _, _ in }
            )
            #expect(duplicate == nil)
            await Task.yield()
            order.append(id)
            active -= 1
            return id
        } onResult: { _, _ in }
        #expect(results == [0, 1, 2])
        #expect(order == [0, 1, 2])
        let later = await coordinator.run(
            activities: [4],
            limit: 1,
            execute: { $0 },
            onResult: { _, _ in }
        )
        #expect(later == [4])
    }

    @Test func cancellationRetainsFinishedResultsAndDoesNotStartQueuedWork() async {
        let coordinator = BackgroundActivityCoordinator()
        var started: [Int] = []
        var delivered: [Int] = []
        let work = Task { @MainActor in
            await coordinator.run(activities: [0, 1, 2], limit: 1) { id in
                started.append(id)
                return id
            } onResult: { _, result in
                delivered.append(result)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let results = await work.value
        #expect(results == [0])
        #expect(started == [0])
        #expect(delivered == [0])
    }

    @Test func expirationCancelsRunningSiblingAndRetainsFastResult() async {
        let coordinator = BackgroundActivityCoordinator()
        var delivered: [Int] = []
        var started: [Int] = []
        let work = Task { @MainActor in
            await coordinator.run(activities: [0, 1, 2], limit: 2) { id in
                started.append(id)
                if id == 1 {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return -1 }
                }
                return id
            } onResult: { _, result in
                if result == 0 {
                    delivered.append(result)
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        let results = await work.value
        #expect(Set(results ?? []) == [0, -1])
        #expect(Set(started) == [0, 1])
        #expect(delivered == [0])
    }

    @Test func lifecycleCompletesOnceOnExpirationRace() {
        var outcomes: [Bool] = []
        let lifecycle = BackgroundOpportunityLifecycle { outcomes.append($0) }
        lifecycle.finish(success: false)
        lifecycle.finish(success: true)
        #expect(outcomes == [false])
    }
}

@Suite("Background activity completion", .serialized)
@MainActor
struct BackgroundActivityCompletionTests {
    @Test func onlyCompletedActivitiesCommitCooldownBeforeDelivery() async throws {
        let suite = "background-completion-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 200_000)
        let completed = await BackgroundPromptService.runActivities(
            modes: [.preparation, .maintenance], limit: 3, defaults: defaults, now: { now },
            execute: { mode in
                BackgroundPromptService.Result(status: mode == .preparation ? .completed : .failed)
            },
            onResult: { result in
                if result.status == .completed {
                    #expect(defaults
                        .object(forKey: BackgroundRunMode.preparation.lastRunKey) as? Date == now)
                }
            }
        )
        #expect(completed?.count == 2)
        #expect(BackgroundPromptService
            .eligibleModes(now: now, defaults: defaults) == [.maintenance, .reflection])
        let cancelled = await BackgroundPromptService.runActivities(
            modes: [.maintenance], limit: 1, defaults: defaults,
            execute: { _ in .init(status: .cancelled) }
        )
        #expect(cancelled?.first?.status == .cancelled)
        #expect(defaults.object(forKey: BackgroundRunMode.maintenance.lastRunKey) == nil)
    }

    @Test func streamInterruptionAfterFirstTokenLeavesActivityDue() async throws {
        let suite = "background-preemption-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = Provider(name: "Test", baseURL: "https://model.invalid")
        let agent = Agent(name: "Wren", providerID: provider.id, model: "test")
        let model = FakeChatService()
        model.enqueueEventStream([.contentDelta("Partial")], endingWith: CancellationError())
        let results = await BackgroundPromptService.runActivities(
            modes: [.maintenance], limit: 1, defaults: defaults,
            execute: { _ in
                do {
                    _ = try await BackgroundPromptService.runChatLoop(
                        apiMessages: [.init(role: "user", content: "Start")],
                        registry: ToolRegistry(tools: []),
                        agent: agent, provider: provider, chatService: model,
                        signalBox: BackgroundSignalBox(), skillSession: nil,
                        accessPolicy: .init(currentSpaceID: nil, publicSpaceIDs: []),
                        permissionPolicy: AlwaysAllowPolicy()
                    )
                    return .init(status: .completed)
                } catch is CancellationError { return .init(status: .cancelled) }
                catch { return .init(status: .failed) }
            }
        )
        #expect(results?.first?.status == .cancelled)
        #expect(defaults.object(forKey: BackgroundRunMode.maintenance.lastRunKey) == nil)
    }

    @Test func expirationPreservesSavedResultWhenNotificationPermissionIsDenied() async throws {
        let suite = "background-expiration-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Wren", providerID: UUID(), model: "test")
        container.mainContext.insert(agent)
        try container.mainContext.save()
        let agentID = agent.id
        var expiration: (@Sendable () -> Void)?
        var completed: [Bool] = []
        var reschedules = 0
        var activityResults: [BackgroundPromptService.Result] = []
        let work = BackgroundPromptScheduler.start(
            installExpiration: { expiration = $0 },
            reschedule: { reschedules += 1 }, complete: { completed.append($0) },
            run: { onResult in
                let results = await BackgroundPromptService.runActivities(
                    modes: [.preparation, .maintenance], limit: 3, defaults: defaults,
                    execute: { mode in
                        if mode == .maintenance {
                            do { try await Task.sleep(for: .seconds(5)) }
                            catch { return .init(status: .cancelled) }
                            return .init(status: .failed)
                        }
                        return .init(
                            didNotify: true,
                            agentID: agentID,
                            notificationTitle: "Ready",
                            notificationBody: "Finding"
                        )
                    }, onResult: onResult
                )
                activityResults = results ?? []
                return results.map(BackgroundPromptService.Opportunity.ran) ?? .busy
            },
            deliver: { result in
                var scheduler = DefaultFollowUpScheduler(container: container)
                scheduler.authorize = { _ in false }
                let delivery = await BackgroundPromptScheduler.deliver(
                    result,
                    container: container,
                    scheduler: scheduler
                )
                if case .saved(.permissionDenied) = delivery {}
                else { Issue.record("Expected persisted permission denial") }
                expiration?()
                return delivery
            }
        )
        await work.value
        #expect(completed == [false])
        #expect(reschedules == 1)
        #expect(activityResults.contains { $0.status == .cancelled })
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 1)
        #expect(defaults.object(forKey: BackgroundRunMode.preparation.lastRunKey) != nil)
        #expect(defaults.object(forKey: BackgroundRunMode.maintenance.lastRunKey) == nil)
    }

    @Test func failedSiblingDoesNotDiscardCompletedActivity() async {
        let coordinator = BackgroundActivityCoordinator()
        var delivered: [Int] = []
        let results = await coordinator.run(activities: [0, 1, 2], limit: 3) { id in
            BackgroundPromptService.Result(status: id == 1 ? .failed : .completed)
        } onResult: { id, result in
            if result.status == .completed { delivered.append(id) }
        }
        #expect(results?.count == 3)
        #expect(Set(delivered) == [0, 2])
    }
}
