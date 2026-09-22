import Foundation
import os

/// Thrown when nobody speaks within the race's ceiling budget: either a first
/// expiry with a hook that has no replacement, or a second expiry where
/// nobody — replacement or runner-up — spoke in time.
struct FirstEventTimeout: Error {}

/// The race's winning model — whichever side spoke first. The racing stream
/// reports it here; the consuming loop reads it once to adopt the turn's model.
final class RaceWinner: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: String?.none)

    /// The winning model, or nil while the race is undecided.
    var current: String? {
        lock.withLock { $0 }
    }

    /// First call wins; later calls are ignored.
    func set(_ model: String) {
        lock.withLock {
            if $0 == nil { $0 = model }
        }
    }
}

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
func withHedgedFirstToken<T: Sendable>(
    primaryModel: String,
    plan: HedgePlan?,
    ceiling: Duration,
    raceWinner: RaceWinner,
    openPrimary: @escaping @Sendable (String) async throws -> AsyncThrowingStream<T, Error>,
    openFallback: @escaping @Sendable () async -> AsyncThrowingStream<T, Error>?,
    primaryFailed: @escaping @Sendable (String, Error) async -> (
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
            raceWinner: raceWinner,
            openPrimary: openPrimary,
            openFallback: openFallback,
            primaryFailed: primaryFailed,
            onLoser: onLoser,
            continuation: continuation
        )
        race.start()
        continuation.onTermination = { _ in race.cancel() }
    }
}

/// One side of the race.
private enum RaceSide: Sendable, CustomStringConvertible {
    case primary
    case fallback

    var description: String {
        switch self {
        case .primary: "primary"
        case .fallback: "runner-up"
        }
    }
}

/// Coordinates the lazily-opened primary stream, the runner-up once opened, and
/// the ceiling watchdog. The first event from either side wins; a side that
/// loses is cancelled and its late events dropped. All clocks tick from
/// `start()`, covering the primary's dispatch.
private final class HedgeRace<T: Sendable>: @unchecked Sendable {
    private struct State {
        var winner: RaceSide?
        var finished = false
        /// The model the primary side currently carries — updated when the
        /// failure hook hands back a replacement under a different model.
        var currentPrimaryModel: String
        /// The runner-up once its stream is attached. Dispatch, or a stream
        /// still awaiting headers, is not attached.
        var fallback = Attached()
        /// Pre-winner deaths. Both sides dead ends the race immediately, with
        /// whichever error surfaced, instead of the ceiling's timeout.
        var primaryDeath = Death()
        var fallbackDeath = Death()
        var primaryForwarding: Task<Void, Never>?
        var fallbackForwarding: Task<Void, Never>?
        var hedgeTimer: Task<Void, Never>?
        var watchdog: Task<Void, Never>?

        struct Attached {
            var opened = false
            var dispatchedAt = ContinuousClock.Instant?.none
        }

        struct Death {
            var dead = false
            var surfacedError = Error?.none
        }

        /// Spent by the first expiry that reaches a decision. A second
        /// expiry — a rearmed ceiling that nobody met — fails the race.
        var timeoutChaseUsed = false
        /// One chase at a time: concurrent initiators (expiry + stream death)
        /// would otherwise record the failure twice and race two replacements.
        var chaseInFlight = false

        var tasks: [Task<Void, Never>] {
            [primaryForwarding, fallbackForwarding, hedgeTimer, watchdog].compactMap { $0 }
        }
    }

    private struct Decision {
        var accepted = false
        var winnerModel: String?
        var loserModel: String?
        var loserForwarding: Task<Void, Never>?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State(currentPrimaryModel: ""))

    private let primaryModel: String
    private let plan: HedgePlan?
    private let ceiling: Duration
    private let raceWinner: RaceWinner
    private let openPrimary: @Sendable (String) async throws -> AsyncThrowingStream<T, Error>
    private let openFallback: @Sendable () async -> AsyncThrowingStream<T, Error>?
    private let primaryFailed: @Sendable (String, Error) async -> (
        model: String,
        stream:
        AsyncThrowingStream<T, Error>
    )?
    private let onLoser: @Sendable (String, Duration) async -> Void
    private let continuation: AsyncThrowingStream<T, Error>.Continuation
    /// Silence origin for a losing primary, matching time-to-first-token origin.
    private let dispatchedAt = ContinuousClock.now

    init(
        primaryModel: String,
        plan: HedgePlan?,
        ceiling: Duration,
        raceWinner: RaceWinner,
        openPrimary: @escaping @Sendable (String) async throws -> AsyncThrowingStream<T, Error>,
        openFallback: @escaping @Sendable () async -> AsyncThrowingStream<T, Error>?,
        primaryFailed: @escaping @Sendable (String, Error) async -> (
            model: String,
            stream:
            AsyncThrowingStream<T, Error>
        )?,
        onLoser: @escaping @Sendable (String, Duration) async -> Void,
        continuation: AsyncThrowingStream<T, Error>.Continuation
    ) {
        self.primaryModel = primaryModel
        self.plan = plan
        self.ceiling = ceiling
        self.raceWinner = raceWinner
        self.openPrimary = openPrimary
        self.openFallback = openFallback
        self.primaryFailed = primaryFailed
        self.onLoser = onLoser
        self.continuation = continuation
        lock.withLock { $0.currentPrimaryModel = primaryModel }
    }

    func start() {
        startWatchdog()
        if plan != nil { startHedgeTimer() }
        let task = Task { [self] in await primarySide() }
        lock.withLock { $0.primaryForwarding = task }
    }

    /// The consumer walked away: stop everything, including any in-flight dispatch.
    func cancel() {
        let tasks = lock.withLock { state -> [Task<Void, Never>] in
            state.finished = true
            return state.tasks
        }
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Timers

    private func startWatchdog() {
        let task = Task { [self] in
            try? await Task.sleep(for: ceiling)
            guard !Task.isCancelled else { return }
            expired()
        }
        // Replace, don't append: overlapping starters (a rearmed ceiling and
        // a guard-restarted one) must leave exactly one ticker running.
        lock.withLock { state in
            state.watchdog?.cancel()
            state.watchdog = task
        }
    }

    /// Nothing spoke anywhere within the ceiling. The first expiry hands the
    /// timeout to the chase hook once — it may re-dispatch under a model that
    /// answers within a rearmed ceiling. A live runner-up keeps that fresh
    /// ceiling itself (the hook can't answer for it). The second expiry fails
    /// the race: nobody spoke in two ceilings.
    private func expired() {
        let decision: ExpiryDecision = lock.withLock { state in
            guard !state.finished, state.winner == nil else { return .ignore }
            if state.timeoutChaseUsed {
                state.finished = true
                return .fail
            }
            state.timeoutChaseUsed = true
            return !state.fallback.opened || state.fallbackDeath.dead
                ? .chase
                : .rearm
        }
        switch decision {
        case .ignore:
            break
        case .fail:
            cancelTasks()
            continuation.finish(throwing: FirstEventTimeout())
        case .rearm:
            startWatchdog()
        case .chase:
            // The consumed watchdog is done; drop it so nothing expired lingers.
            lock.withLock { $0.watchdog = nil }
            let model = lock.withLock { $0.currentPrimaryModel }
            Task { [self] in
                await handlePrimaryFailure(model, FirstEventTimeout())
                // The runner-up may have attached while the hook ran. If the
                // chase was then abandoned (the hook can't answer for a live
                // side, or the race closed meanwhile), the live runner-up
                // still owes a ceiling — otherwise a fully silent race would
                // sit with no timers at all.
                let needsClock = lock.withLock { state -> Bool in
                    !state.finished && state.winner == nil
                        && state.fallback.opened && !state.fallbackDeath.dead
                }
                if needsClock { startWatchdog() }
            }
        }
    }

    private enum ExpiryDecision: Sendable {
        /// The race was decided or finished since the timer fired.
        case ignore
        /// The chase was already spent: fail instead of waiting forever.
        case fail
        /// A live runner-up gets a fresh ceiling.
        case rearm
        /// Hand the timeout to the chase hook.
        case chase
    }

    private func startHedgeTimer() {
        let task = Task { [self] in
            try? await Task.sleep(for: plan?.delay ?? .zero)
            guard !Task.isCancelled else { return }
            await openRunnerUp()
        }
        lock.withLock { $0.hedgeTimer = task }
    }

    private func openRunnerUp() async {
        let raceOpen = lock.withLock { state -> Bool in
            !state.finished && state.winner == nil
        }
        guard raceOpen, let fallback = await openFallback() else { return }

        // The race may have closed while the dispatch was in flight.
        let attached = lock.withLock { state -> Bool in
            guard !state.finished, state.winner == nil else { return false }
            state.fallback.opened = true
            state.fallback.dispatchedAt = state.fallback.dispatchedAt ?? ContinuousClock.now
            state.fallbackForwarding = Task { [self] in await forward(.fallback, fallback) }
            return true
        }
        if !attached {
            // The race closed while dispatching; dropping the stream tears it down.
            _ = fallback
        }
    }

    // MARK: - Primary side

    /// Lazily opens the primary and forwards it; failures consult `primaryFailed`,
    /// which may hand back a replacement under a different model.
    private func primarySide() async {
        while !Task.isCancelled {
            let model = lock.withLock { $0.currentPrimaryModel }
            do {
                let stream = try await openPrimary(model)
                await forward(.primary, stream)
                return
            } catch {
                let recovered = await handlePrimaryFailure(model, error)
                guard recovered else {
                    return
                }
            }
        }
    }

    /// Decides whether a primary-side failure can be chased. True only for an
    /// undecided race with no fallback yet attached — anything else is either a
    /// settled loser (swallow) or already covered by the fallback stream. One
    /// chase runs at a time: concurrent initiators would otherwise record the
    /// failure twice and race two replacements.
    private func handlePrimaryFailure(_ failedModel: String, _ error: Error) async -> Bool {
        let claimed = lock.withLock { state -> Bool in
            !state.finished && state.winner == nil
                && (!state.fallback.opened || state.fallbackDeath.dead)
                && !state.chaseInFlight
        }
        guard claimed else { return false }
        defer { lock.withLock { $0.chaseInFlight = false } }

        guard let replacement = await primaryFailed(failedModel, error) else {
            // Nothing to switch to — surface the error to the consumer.
            finish(throwing: error)
            return false
        }

        let decided = lock.withLock { state -> Bool in
            guard !state.finished, state.winner == nil else { return false }
            state.currentPrimaryModel = replacement.model
            // A replacement gets a fresh ceiling: the old window was the
            // original primary's.
            state.watchdog?.cancel()
            state.watchdog = nil
            return true
        }
        guard decided else {
            // The race closed while switching; dropping the stream tears it down.
            _ = replacement.stream
            return false
        }
        startWatchdog()
        AppLogger.info(
            "Primary \(public: failedModel) failed (\(public: String(describing: error))); racing on \(public: replacement.model)",
            category: .routing
        )
        await forward(.primary, replacement.stream)
        return false
    }

    // MARK: - Forwarding

    private func forward(
        _ side: RaceSide,
        _ stream: AsyncThrowingStream<T, Error>
    ) async {
        do {
            for try await element in stream {
                guard claim(side) else { return }
                continuation.yield(element)
            }
            ended(side, nil)
        } catch {
            ended(side, error)
        }
    }

    /// Whether `side` may forward an element. The first event anywhere makes its
    /// side the winner: the model is attributed to the turn, and the other side —
    /// if it had actually opened — is cancelled and reported as having gone
    /// silent. Returns false for a settled loser.
    private func claim(_ side: RaceSide) -> Bool {
        let decision = lock.withLock { state -> Decision in
            guard !state.finished else { return Decision() }
            if let winner = state.winner {
                return Decision(accepted: winner == side)
            }
            state.winner = side
            state.hedgeTimer?.cancel()
            state.hedgeTimer = nil
            state.watchdog?.cancel()
            state.watchdog = nil

            if side == .primary {
                guard state.fallback.opened, let task = state.fallbackForwarding else {
                    return Decision(accepted: true, winnerModel: state.currentPrimaryModel)
                }
                state.fallbackForwarding = nil
                return Decision(
                    accepted: true,
                    winnerModel: state.currentPrimaryModel,
                    loserModel: plan?.fallbackModel,
                    loserForwarding: task
                )
            }
            let task = state.primaryForwarding
            state.primaryForwarding = nil
            return Decision(
                accepted: true,
                winnerModel: plan?.fallbackModel,
                loserModel: state.currentPrimaryModel,
                loserForwarding: task
            )
        }

        guard decision.accepted else { return false }
        if let winnerModel = decision.winnerModel {
            raceWinner.set(winnerModel)
        }
        if let loserForwarding = decision.loserForwarding {
            loserForwarding.cancel()
            let loserModel = decision.loserModel ?? ""
            // Measure the loser's silence from when the loser itself began.
            let loserSide: RaceSide = side == .primary ? .fallback : .primary
            let silentFor = silenceOrigin(of: loserSide).duration(to: .now)
            Task { await onLoser(loserModel, silentFor) }
        }
        return true
    }

    private func ended(_ side: RaceSide, _ error: Error?) {
        let terminalError = error ?? {
            if case .fallback = side { return PrimaryStreamEnded() }
            return nil
        }()

        // A primary-side failure on an undecided race with no live runner-up is
        // chased via the failure hook - it may re-dispatch under a different
        // model. A dead runner-up also can't answer for the primary, so a
        // re-dispatch still has something to win.
        if case .primary = side {
            let chase = lock.withLock { state -> Bool in
                !state.finished && state.winner == nil
                    && (!state.fallback.opened || state.fallbackDeath.dead)
            }
            if chase {
                let model = lock.withLock { $0.currentPrimaryModel }
                Task { [self] in
                    await handlePrimaryFailure(model, error ?? PrimaryStreamEnded())
                }
                return
            }
        }

        let finish: Bool = lock.withLock { state -> Bool in
            guard !state.finished else { return false }
            if let winner = state.winner {
                // A settled loser ends into its own cancellation; nothing to do.
                guard winner == side else { return false }
                state.finished = true
                return true
            }
            // Undecided race: this side is now dead. If its counterpart is also
            // dead, nobody can speak anymore - fail now instead of making the
            // user wait out the ceiling on dead streams.
            if case .primary = side {
                state.primaryDeath.dead = true
                state.primaryDeath.surfacedError = state.primaryDeath.surfacedError ?? terminalError
                if state.fallbackDeath.dead {
                    state.finished = true
                    return true
                }
                return false
            }
            state.fallbackDeath.dead = true
            state.fallbackDeath.surfacedError = state.fallbackDeath.surfacedError ?? terminalError
            // The primary either lives (a chase is pending) or is dead; a dead
            // counterpart ends the race here.
            if state.primaryDeath.dead {
                state.finished = true
                return true
            }
            return false
        }

        // The second death picks whichever surfaced error exists - the streams
        // are gone either way.
        if finish {
            cancelTasks()
            let surfaced = lock
                .withLock { $0.primaryDeath.surfacedError ?? $0.fallbackDeath.surfacedError }
            if let surfaced {
                continuation.finish(throwing: surfaced)
            } else {
                continuation.finish()
            }
        }
    }

    /// A primary stream that ended cleanly without a single event.
    private struct PrimaryStreamEnded: Error {}

    /// The loser's silence origin. A losing runner-up is measured from its own
    /// dispatch; a losing primary - including a retry replacement - owes its
    /// silence to the turn, so the race start stands in. Only shapes the
    /// recorded log value, never any decision.
    private func silenceOrigin(of losing: RaceSide) -> ContinuousClock.Instant {
        lock.withLock { state -> ContinuousClock.Instant in
            if case .fallback = losing, let dispatched = state.fallback.dispatchedAt {
                return dispatched
            }
            return dispatchedAt
        }
    }

    private func cancelTasks() {
        let tasks = lock.withLock { state -> [Task<Void, Never>] in
            let tasks = state.tasks
            state.primaryForwarding = nil
            state.fallbackForwarding = nil
            state.hedgeTimer = nil
            state.watchdog = nil
            return tasks
        }
        tasks.forEach { $0.cancel() }
    }

    private func finish(throwing error: Error) {
        lock.withLock {
            guard !$0.finished else { return }
            $0.finished = true
        }
        cancelTasks()
        continuation.finish(throwing: error)
    }
}

/// One turn's event stream plus the race bookkeeping its consumer needs
/// (the winning model, chosen switches, failures already recorded).
struct TurnStream: Sendable {
    /// How many models one turn's race may hand the primary side before
    /// surfacing the error. The hedge loser is free — it isn't a switch.
    static let maxModelSwitches = 2

    let stream: AsyncThrowingStream<ChatStreamEvent, Error>
    let dispatchedAt: ContinuousClock.Instant
    let raceWinner: RaceWinner
    /// Set by the retry hook whenever the primary side switched models; the
    /// consuming loop persists the agent's model once that model carries the
    /// turn (same-actor state, so the switch is user-visible only when real).
    var switchCandidate = OSAllocatedUnfairLock(initialState: String?.none)
    /// Set by the retry hook when it surfaces an error it already recorded;
    /// the consuming loop then skips reporting that failure again.
    var failureReported = OSAllocatedUnfairLock(initialState: false)
}
