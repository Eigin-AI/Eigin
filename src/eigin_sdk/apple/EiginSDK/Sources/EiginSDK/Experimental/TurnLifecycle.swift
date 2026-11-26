import EiginSDKBindings
import Foundation

/// Carries callback cancellation to the turn boundary that admits its effects.
final class TurnLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private weak var operation: ChatTurnOperation?
    private var callbackCancelled = false
    private var streaming = false
    private var stopped = false

    func attach(_ operation: ChatTurnOperation) {
        lock.withLock { self.operation = operation }
    }

    func stop() {
        lock.withLock { stopped = true }
    }

    func checkPreparation() throws {
        if lock.withLock({ callbackCancelled }) { throw CancellationError() }
    }

    func willObserve(_ event: ChatTurnEvent) {
        lock.withLock {
            switch event {
            case .requestOpened: streaming = true
            case .requestReported: streaming = false
            default: break
            }
        }
    }

    func didObserve(_ event: ChatTurnEvent) {
        if case .inference(.contentDelta) = event { cancelIfCurrentTaskCancelled() }
    }

    func didPresent(_ work: EiginSDKBindings.TurnPresentation) {
        switch work {
        case .finishToolProse, .afterTool: latchCancellation()
        case .beforeTool, .drain:
            if Task.isCancelled || lock.withLock({ callbackCancelled }) { cancel() }
        }
    }

    func cancelIfCurrentTaskCancelled() {
        if Task.isCancelled { cancel() }
    }

    func latchCancellation() {
        let cancelled = Task.isCancelled
        lock.withLock { callbackCancelled = callbackCancelled || cancelled }
    }

    func signals(
        at boundary: TurnSignalBoundary,
        completionRequested: @Sendable () async -> Bool
    ) async -> TurnSignals {
        let before = Task.isCancelled || lock.withLock { callbackCancelled }
        let shouldCheck = lock.withLock { !stopped } && (boundary != .failure || !before)
        let terminate = shouldCheck ? await completionRequested() : false
        latchCancellation()
        return lock.withLock {
            .init(cancelled: boundary == .emptyReply ? callbackCancelled : before,
                  stopped: stopped, terminate: terminate)
        }
    }

    func returnsStoppedOutput(for error: any Error, propagateStreamCancellation: Bool) -> Bool {
        lock.withLock {
            stopped || (error is CancellationError && streaming && !propagateStreamCancellation)
        }
    }

    private func cancel() {
        let operation = lock.withLock { self.operation }
        operation?.cancel()
    }
}
