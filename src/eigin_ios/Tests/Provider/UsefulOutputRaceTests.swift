@testable import Eigin
import Foundation
import os
import Testing

@Suite("Useful-output race")
struct UsefulOutputRaceTests {
    private func stream(_ events: [ChatStreamEvent])
        -> AsyncThrowingStream<ChatStreamEvent, Error>
    {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    @Test func metadataCannotBeatUsefulFallback() async throws {
        let primary = AsyncThrowingStream<ChatStreamEvent, Error>.makeStream()
        primary.continuation.yield(.providerMetadata(["side": "loser"]))
        let events: [ChatStreamEvent] = [
            .providerMetadata(["side": "winner"]), .contentDelta("Answer"), .finished(.stop),
        ]
        let fallback = stream(events)
        let winner = RaceWinner()
        let race = withHedgedFirstToken(
            primaryModel: "primary", plan: HedgePlan(
                delay: .milliseconds(10),
                fallbackModel: "fallback"
            ),
            ceiling: .seconds(1), raceWinner: winner,
            isWinningEvent: { $0.isUsefulOutput }, bufferedEventBytes: { $0.bufferedByteCount },
            openPrimary: { _ in primary.stream }, openFallback: { fallback },
            primaryFailed: { _, _ in nil }, onLoser: { _, _ in }
        )
        var received: [ChatStreamEvent] = []
        for try await event in race {
            received.append(event)
        }
        #expect(winner.current == "fallback")
        #expect(received == events)
    }

    @Test func invalidToolArgumentsCannotBeatUsefulFallback() async throws {
        let primary = AsyncThrowingStream<ChatStreamEvent, Error>.makeStream()
        primary.continuation.yield(.toolCall(ToolCall(
            id: "invalid", type: "function", function: .init(name: "search", arguments: "{broken")
        )))
        let fallback = stream([.contentDelta("Answer"), .finished(.stop)])
        let winner = RaceWinner()
        let race = withHedgedFirstToken(
            primaryModel: "primary", plan: HedgePlan(
                delay: .milliseconds(10),
                fallbackModel: "fallback"
            ),
            ceiling: .seconds(1), raceWinner: winner,
            isWinningEvent: { $0.isUsefulOutput }, bufferedEventBytes: { $0.bufferedByteCount },
            openPrimary: { _ in primary.stream }, openFallback: { fallback },
            primaryFailed: { _, _ in nil }, onLoser: { _, _ in }
        )
        var received: [ChatStreamEvent] = []
        for try await event in race {
            received.append(event)
        }
        #expect(received == [.contentDelta("Answer"), .finished(.stop)])
        #expect(winner.current == "fallback")
    }

    @Test func overflowRetriesThroughRealRouterWithoutQuarantiningModel() async throws {
        let provider = RoutingProvider(
            id: UUID(), name: "Mistral", baseURL: "https://api.mistral.ai/v1",
            availableModels: ["mistral-large-4-0", "mistral-medium-3-5"]
        )
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { false }
        )
        let request = RouteRequest(
            currentProviderID: provider.id, currentModel: "mistral-large-4-0", isAuto: true,
            requirements: RouteRequirements(), providers: [provider], conversationID: UUID()
        )
        let primary = stream([.providerMetadata(["status": String(repeating: "x", count: 1024)])])
        let replacement = stream([.contentDelta("Replacement"), .finished(.stop)])
        let winner = RaceWinner()
        let race = withHedgedFirstToken(
            primaryModel: request.currentModel, plan: nil, ceiling: .seconds(1), raceWinner: winner,
            isWinningEvent: { $0.isUsefulOutput }, bufferedEventBytes: { $0.bufferedByteCount },
            maxBufferedBytes: 256,
            openPrimary: { _ in primary }, openFallback: { nil },
            primaryFailed: { _, error in
                guard let route = await router.retry(after: error, request: request)
                else { return nil }
                return (model: route.model, stream: replacement)
            }, onLoser: { _, _ in }
        )
        var received: [ChatStreamEvent] = []
        for try await event in race {
            received.append(event)
        }
        #expect(received == [.contentDelta("Replacement"), .finished(.stop)])
        #expect(winner.current == "mistral-medium-3-5")
        let fresh = RouteRequest(
            currentProviderID: provider.id, currentModel: request.currentModel, isAuto: true,
            requirements: RouteRequirements(), providers: [provider], conversationID: UUID()
        )
        #expect(await router.resolve(fresh).model == request.currentModel)
    }

    @Test func metadataDoesNotDisableCeiling() async {
        let primary = AsyncThrowingStream<ChatStreamEvent, Error>.makeStream()
        primary.continuation.yield(.providerMetadata(["status": "thinking"]))
        let winner = RaceWinner()
        let race = withHedgedFirstToken(
            primaryModel: "primary", plan: nil, ceiling: .milliseconds(20), raceWinner: winner,
            isWinningEvent: { $0.isUsefulOutput }, bufferedEventBytes: { $0.bufferedByteCount },
            openPrimary: { _ in primary.stream }, openFallback: { nil },
            primaryFailed: { _, _ in nil }, onLoser: { _, _ in }
        )
        do {
            for try await _ in race {
                Issue.record("Metadata must remain buffered")
            }
            Issue.record("Expected first-output timeout")
        } catch { #expect(error is FirstEventTimeout) }
        #expect(winner.current == nil)
    }

    @Test(arguments: [false, true])
    func nonUsefulCompletionOrOverflowRetries(overflow: Bool) async throws {
        let primary = stream([.providerMetadata(["status": "thinking"]), .finished(.stop)])
        let replacement = stream([.contentDelta("Replacement"), .finished(.stop)])
        let winner = RaceWinner()
        let race = withHedgedFirstToken(
            primaryModel: "primary", plan: nil, ceiling: .seconds(1), raceWinner: winner,
            isWinningEvent: { $0.isUsefulOutput }, bufferedEventBytes: { $0.bufferedByteCount },
            maxBufferedBytes: overflow ? 1 : 1024,
            openPrimary: { _ in primary }, openFallback: { nil },
            primaryFailed: { _, _ in (model: "replacement", stream: replacement) },
            onLoser: { _, _ in }
        )
        var received: [ChatStreamEvent] = []
        for try await event in race {
            received.append(event)
        }
        #expect(received == [.contentDelta("Replacement"), .finished(.stop)])
        #expect(winner.current == "replacement")
    }

    @Test func staleDispatchFailureCannotReplaceActiveChase() async throws {
        let original = AsyncThrowingStream<ChatStreamEvent, Error>.makeStream()
        let replacement = AsyncThrowingStream<ChatStreamEvent, Error>.makeStream()
        let chased = AsyncStream<Void>.makeStream()
        let failures = OSAllocatedUnfairLock(initialState: 0)
        let winner = RaceWinner()
        let race = withHedgedFirstToken(
            primaryModel: "primary", plan: nil, ceiling: .milliseconds(100), raceWinner: winner,
            isWinningEvent: { $0.isUsefulOutput }, bufferedEventBytes: { $0.bufferedByteCount },
            openPrimary: { _ in
                for try await _ in original.stream {}
                return original.stream
            },
            openFallback: { nil },
            primaryFailed: { _, _ in
                failures.withLock { $0 += 1 }
                chased.continuation.yield(())
                return (model: "replacement", stream: replacement.stream)
            }, onLoser: { _, _ in }
        )
        let consumer = Task { () throws -> [ChatStreamEvent] in
            var received: [ChatStreamEvent] = []
            for try await event in race {
                received.append(event)
            }
            return received
        }
        for await _ in chased.stream {
            break
        }
        original.continuation.finish(throwing: URLError(.timedOut))
        try await Task.sleep(for: .milliseconds(20))
        replacement.continuation.yield(.contentDelta("Replacement"))
        replacement.continuation.finish()
        #expect(try await consumer.value == [.contentDelta("Replacement")])
        #expect(failures.withLock { $0 } == 1)
        #expect(winner.current == "replacement")
    }

    @Test func toolCallWinsAndPreservesMetadata() async throws {
        let tool = ToolCall(
            id: "call",
            type: "function",
            function: .init(name: "search", arguments: "{}")
        )
        let events: [ChatStreamEvent] = [
            .providerMetadata(["signature": "value"]),
            .toolCall(tool),
            .finished(.toolCalls),
        ]
        let primary = stream(events)
        let race = withHedgedFirstToken(
            primaryModel: "primary", plan: nil, ceiling: .seconds(1), raceWinner: RaceWinner(),
            isWinningEvent: { $0.isUsefulOutput }, bufferedEventBytes: { $0.bufferedByteCount },
            openPrimary: { _ in primary }, openFallback: { nil },
            primaryFailed: { _, _ in nil }, onLoser: { _, _ in }
        )
        var received: [ChatStreamEvent] = []
        for try await event in race {
            received.append(event)
        }
        #expect(received == events)
        #expect(!ChatStreamEvent.contentDelta("").isUsefulOutput)
        #expect(!ChatStreamEvent.performance(.init(timeToFirstToken: nil, tokensPerSecond: nil))
            .isUsefulOutput)
    }
}
