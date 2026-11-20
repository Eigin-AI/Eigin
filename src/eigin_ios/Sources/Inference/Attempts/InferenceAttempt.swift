import EiginSDK
import Foundation

/// A stream and its router attribution for one SDK inference request.
@MainActor
final class InferenceAttempt {
    let stream: AsyncThrowingStream<ChatStreamEvent, Error>
    private let selection: EiginSDK.Experimental.Inference.Attempts
    private let providerID: UUID
    private let dispatchedAt: ContinuousClock.Instant
    private let router: any ModelRouter

    private var firstTokenAt: ContinuousClock.Instant?
    private var performance: InferencePerformance?

    init(
        stream: AsyncThrowingStream<ChatStreamEvent, Error>,
        selection: EiginSDK.Experimental.Inference.Attempts,
        providerID: UUID,
        dispatchedAt: ContinuousClock.Instant,
        router: any ModelRouter
    ) {
        self.stream = stream
        self.selection = selection
        self.providerID = providerID
        self.dispatchedAt = dispatchedAt
        self.router = router
    }

    /// Samples only events the consumer accepted into this round.
    func observe(_ event: ChatStreamEvent) {
        switch event {
        case .contentDelta(let text) where !text.isEmpty && firstTokenAt == nil: firstTokenAt = .now
        case .performance(let measured): performance = measured
        default: break
        }
    }

    var winningModel: String {
        selection.winningModel()
    }

    var retryWon: Bool {
        selection.retryWon()
    }

    func report(sentAt: ContinuousClock.Instant?, result: AttemptOutcome.Result) async {
        let measured: InferencePerformance? = if case .succeeded = result { performance }
        else { nil }
        let ttft = measured?.timeToFirstToken ?? firstTokenAt.map { dispatchedAt.duration(to: $0) }
        logTurnTiming(
            prep: sentAt.map { $0.duration(to: dispatchedAt) },
            modelTTFT: ttft,
            result: result
        )
        let failed = if case .failed = result { true } else { false }
        guard selection.shouldReport(failed: failed, observedContent: firstTokenAt != nil)
        else { return }
        await router.record(AttemptOutcome(
            providerID: providerID,
            model: winningModel,
            timeToFirstToken: ttft,
            tokensPerSecond: measured?.tokensPerSecond,
            duration: dispatchedAt.duration(to: .now),
            result: result
        ))
    }

    private func logTurnTiming(
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
}
