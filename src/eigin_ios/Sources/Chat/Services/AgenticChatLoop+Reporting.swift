import Foundation

/// Turn bookkeeping: timing logs and the attempt reports that feed the router's
/// health samples. Split from the turn loop's core file to keep each readable.
extension AgenticChatLoop {
    func logTurnTiming(
        prep: Duration?, modelTTFT: Duration?, result: AttemptOutcome.Result
    ) {
        let outcome = switch result {
        case .succeeded: "done"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
        func format(_ duration: Duration?) -> String {
            guard let duration else { return "n/a" }
            let seconds = Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
            return String(format: "%.2fs", seconds)
        }
        let perceived: Duration? = {
            guard let prep, let modelTTFT else { return nil }
            return prep + modelTTFT
        }()
        AppLogger.info(
            "Turn timing (\(public: outcome)): prep send→dispatch \(public: format(prep)), model TTFT \(public: format(modelTTFT)), perceived TTFT \(public: format(perceived))",
            category: .chat
        )
    }

    /// Adopts the race winner as the turn's model: hedge runner-up or a retried
    /// primary replaces the dispatched model for every later record, retry, and
    /// report. A switch the standing retry chose is persisted back to the agent,
    /// now that its model demonstrably carries the turn.
    func adoptTurnModel(_ turn: TurnStream, providerID: UUID, agent: Agent) {
        guard let winner = turn.raceWinner.current, winner != activeModel else { return }
        AppLogger.info("Race winner \(public: winner) carries the turn", category: .chat)
        activeModel = winner
        if turn.switchCandidate.withLock({ $0 }) == winner, agent.providerID == providerID {
            agent.model = winner
        }
    }

    /// Reports one stream's outcome to the router, with the turn's timing.
    ///
    /// Throughput is estimated from the prose actually streamed, at the usual four
    /// characters per token. Tool-call arguments are excluded, so a tool-heavy round
    /// under-reports rather than inventing precision the stream cannot give us.
    func reportAttempt(
        provider: Provider,
        start: ContinuousClock.Instant,
        firstTokenAt: ContinuousClock.Instant?,
        result: AttemptOutcome.Result
    ) async {
        logTurnTiming(
            prep: turnSentAt.map { $0.duration(to: start) },
            modelTTFT: firstTokenAt.map { start.duration(to: $0) },
            result: result
        )
        let duration = start.duration(to: .now)
        let tokensPerSecond: Double? = {
            guard let firstTokenAt, contentBuffer.count >= 40 else { return nil }
            let generating = firstTokenAt.duration(to: .now).seconds
            guard generating > 0 else { return nil }
            return (Double(contentBuffer.count) / 4) / generating
        }()
        await modelRouter.record(
            AttemptOutcome(
                providerID: provider.id,
                model: activeModel,
                timeToFirstToken: firstTokenAt.map { start.duration(to: $0) },
                tokensPerSecond: tokensPerSecond,
                duration: duration,
                result: result
            )
        )
    }
}
