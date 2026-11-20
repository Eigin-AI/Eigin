import EiginSDK
import Foundation

/// Thrown when nobody speaks within the race's ceiling budget: either a first
/// expiry with a hook that has no replacement, or a second expiry where
/// nobody — replacement or runner-up — spoke in time.
struct FirstEventTimeout: Error {}

/// A stream ended before producing an eligible race-winning event.
struct StreamEndedWithoutUsefulOutput: Error {}

/// A candidate exceeded its in-memory buffer for events preceding its answer.
struct PreWinnerBufferOverflow: Error {}

/// When the runner-up opens, and against which model.
struct HedgePlan: Sendable {
    /// Silence (including dispatch time) before the runner-up is dispatched.
    /// Measured from when the turn's race began, not from when the primary's
    /// response headers arrived — a slow handshake is exactly what to race.
    let delay: Duration
    let fallbackModel: String
}

/// Races a primary stream against a lazily-opened runner-up: both run until
/// one speaks, and the loser is cancelled — the user waits one first token,
/// not two. Dispatch happens no earlier than needed, so the hedge delay and
/// `ceiling` tick from the turn's start and cover a slow handshake.
///
/// `primaryFailed` decides an undecided-race primary failure: it may return a
/// replacement stream (the race continues) or nil (the error surfaces). A
/// failed runner-up dispatch degrades silently to primary-only. No event on
/// either side within `ceiling` expires the clock once: the timeout goes to
/// `primaryFailed` for one chase, then a second silent ceiling fails with
/// ``FirstEventTimeout``.
/// Pre-answer events are held per candidate, up to 1 MiB by default, for replay if it wins.
func withHedgedFirstToken<T: Sendable>(
    primaryModel: String,
    plan: HedgePlan?,
    ceiling: Duration,
    attempts: EiginSDK.Experimental.Inference.Attempts,
    classify: @escaping @Sendable (T) -> EiginSDK.Experimental.Inference
        .CandidateEvent = { _ in .content(nonempty: true) },
    bufferedEventBytes: @escaping @Sendable (T) -> Int = { _ in 1 },
    emptyStreamError: @escaping @Sendable ([T]) -> Error = { _ in
        StreamEndedWithoutUsefulOutput()
    },
    openPrimary: @escaping @Sendable (String) async throws -> AsyncThrowingStream<T, Error>,
    openFallback: @escaping @Sendable () async throws -> AsyncThrowingStream<T, Error>?,
    onOpenFailure: @escaping @Sendable (String, Error) async -> Void = { _, _ in },
    primaryFailed: @escaping @Sendable (UInt64, String, Error) async -> (
        model: String,
        stream: AsyncThrowingStream<
            T, Error
        >
    )?,
    onLoser: @escaping @Sendable (_ model: String, _ silentFor: Duration) async -> Void
) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
        let race = HedgeRace(
            primaryModel: primaryModel,
            plan: plan,
            ceiling: ceiling,
            classify: classify,
            bufferedEventBytes: bufferedEventBytes,
            policy: attempts,
            emptyStreamError: emptyStreamError,
            openPrimary: openPrimary,
            openFallback: openFallback,
            onOpenFailure: onOpenFailure,
            primaryFailed: primaryFailed,
            onLoser: onLoser,
            continuation: continuation
        )
        Task { await race.start() }
        continuation.onTermination = { _ in Task { await race.cancel() } }
    }
}

/// Serializes host observations and performs the SDK's ordered stream actions.
private actor HedgeRace<T: Sendable> {
    typealias Stream = AsyncThrowingStream<T, Error>
    typealias SDK = EiginSDK.Experimental.Inference
    let plan: HedgePlan?
    let ceiling: Duration
    let classify: @Sendable (T) -> EiginSDK.Experimental.Inference.CandidateEvent
    let bufferedEventBytes: @Sendable (T) -> Int
    let policy: SDK.Attempts
    let emptyStreamError: @Sendable ([T]) -> Error
    let openPrimary: @Sendable (String) async throws -> Stream
    let openFallback: @Sendable () async throws -> Stream?
    let onOpenFailure: @Sendable (String, Error) async -> Void
    private var openFailureReport: Task<Void, Never>?
    let primaryFailed: @Sendable (UInt64, String, Error) async -> (model: String, stream: Stream)?
    let onLoser: @Sendable (String, Duration) async -> Void
    let continuation: Stream.Continuation
    let startTime = ContinuousClock.now
    private var hedgeOpenedAt: ContinuousClock.Instant?
    private var models: [UInt64: String]
    private var buffers: [UInt64: [T]] = [:]
    private var errors: [UInt64: Error] = [:]
    private var tasks: [UInt64: Task<Void, Never>] = [:]
    private var deadlineWait: Task<Void, Never>?

    init(
        primaryModel: String,
        plan: HedgePlan?,
        ceiling: Duration,
        classify: @escaping @Sendable (T) -> EiginSDK.Experimental.Inference.CandidateEvent,
        bufferedEventBytes: @escaping @Sendable (T) -> Int,
        policy: SDK.Attempts,
        emptyStreamError: @escaping @Sendable ([T]) -> Error,
        openPrimary: @escaping @Sendable (String) async throws -> Stream,
        openFallback: @escaping @Sendable () async throws -> Stream?,
        onOpenFailure: @escaping @Sendable (String, Error) async -> Void,
        primaryFailed: @escaping @Sendable (UInt64, String, Error) async -> (
            model: String,
            stream: Stream
        )?,
        onLoser: @escaping @Sendable (String, Duration) async -> Void,
        continuation: Stream.Continuation
    ) {
        models = [0: primaryModel]
        models[1] = plan?.fallbackModel
        self.plan = plan
        self.ceiling = ceiling
        self.classify = classify
        self.bufferedEventBytes = bufferedEventBytes
        self.policy = policy
        self.emptyStreamError = emptyStreamError
        self.openPrimary = openPrimary
        self.openFallback = openFallback
        self.onOpenFailure = onOpenFailure
        self.primaryFailed = primaryFailed
        self.onLoser = onLoser
        self.continuation = continuation
    }

    func start() {
        apply(.start(
            hedgeDelayMs: plan.map { UInt32(clamping: $0.delay.milliseconds) },
            ceilingMs: UInt32(clamping: ceiling.milliseconds)
        ))
        deadlineWait = Task {
            while await policy.waitForDeadline() {
                perform(policy.drainDeadline())
            }
        }
    }

    func cancel() {
        apply(.cancel)
        stopTasks()
    }

    private func stopTasks() {
        deadlineWait?.cancel()
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func ended(_ id: UInt64, _ error: Error?) {
        errors[id] = error
        apply(.ended(id: id))
    }

    @discardableResult private func apply(
        _ observation: SDK.Observation,
        id source: UInt64 = 0,
        event: T? = nil,
        stream: Stream? = nil
    ) -> Bool {
        perform(policy.step(observation: observation), id: source, event: event, stream: stream)
    }

    @discardableResult private func perform(
        _ actions: [SDK.Action],
        id source: UInt64 = 0,
        event: T? = nil,
        stream: Stream? = nil
    ) -> Bool {
        for action in actions {
            switch action {
            case .cancelOpening(let id):
                tasks[id]?.cancel()
            case .open(let id):
                tasks[id] = Task {
                    do {
                        let opened: Stream? = if id == 1 { try await openFallback() }
                        else { try await openPrimary(models[id]!) }
                        if let opened { apply(.opened(id: id), stream: opened) }
                    } catch {
                        errors[id] = error
                        apply(.openFailed(id: id))
                    }
                }
            case .forward(let id):
                guard let stream else { preconditionFailure("Missing opened stream") }
                if id == 1 { hedgeOpenedAt = .now }
                tasks[id] = Task {
                    do {
                        for try await element in stream {
                            guard !Task.isCancelled else { return }
                            let kind = classify(element)
                            let bytes = UInt64(max(1, bufferedEventBytes(element)))
                            guard apply(
                                .event(id: id, kind: kind, bytes: bytes),
                                id: id,
                                event: element
                            ) else { return }
                        }
                        if !Task.isCancelled { ended(id, buffers[id].map(emptyStreamError)) }
                    } catch { ended(id, error) }
                }
                buffers[id] = []
            case .recordOpenFailure(let id):
                let model = models[id]!, error = errors[id]!
                openFailureReport = Task { await onOpenFailure(model, error) }
            case .buffer: buffers[source, default: []].append(event!)
            case .overflow:
                tasks[source]?.cancel()
                ended(source, PreWinnerBufferOverflow())
            case .win(let id):
                policy.selected(model: models[id]!)
            case .lose(let id):
                let model = models[id]!
                let duration = (id == 1 ? hedgeOpenedAt ?? startTime : startTime).duration(to: .now)
                if id == 1 {
                    tasks[id]?.cancel()
                } else {
                    for (key, task) in tasks where key != 1 {
                        task.cancel()
                    }
                }
                buffers[id] = nil
                Task { await onLoser(model, duration) }
            case .deliver:
                for prior in buffers.removeValue(forKey: source) ?? [] {
                    continuation.yield(prior)
                }
                continuation.yield(event!)
            case .chase(let failed, let replacement, let timeout):
                tasks[failed]?.cancel()
                buffers[failed] = nil
                let model = models[failed]!
                let error: Error = timeout ? FirstEventTimeout() : errors[failed] ??
                    StreamEndedWithoutUsefulOutput()
                models[replacement] = model
                errors[replacement] = error
                let report = openFailureReport
                tasks[replacement] = Task {
                    await report?.value
                    guard !Task.isCancelled else { return }
                    if let next = await primaryFailed(replacement, model, error) {
                        models[replacement] = next.model
                        errors[replacement] = nil
                        apply(.opened(id: replacement), stream: next.stream)
                    } else { apply(.noReplacement(id: replacement)) }
                }
            case .finish(let errorSource, let timeout):
                stopTasks()
                let error = timeout ? FirstEventTimeout() : errors[errorSource]
                if let report = openFailureReport {
                    Task { await report.value; continuation.finish(throwing: error) }
                } else { continuation.finish(throwing: error) }
            }
        }
        return !actions.isEmpty
    }
}
