@testable import Eigin
import Foundation
import Synchronization

/// Controllable inference stream with FluidAudio's closed-input behavior.
final class FakePocketTTSSession: PocketTTSSession, Sendable {
    let frames: AsyncThrowingStream<PocketTTSFrame, Error>
    private let continuation: AsyncThrowingStream<PocketTTSFrame, Error>.Continuation
    private struct State {
        var texts: [String] = []
        var inputFinished = false
        var cancelled = false
    }

    private let state = Mutex(State())

    init() {
        let stream = AsyncThrowingStream<PocketTTSFrame, Error>.makeStream()
        frames = stream.stream
        continuation = stream.continuation
    }

    var texts: [String] {
        state.withLock { $0.texts }
    }

    var inputFinished: Bool {
        state.withLock { $0.inputFinished }
    }

    var cancelled: Bool {
        state.withLock { $0.cancelled }
    }

    func enqueue(_ text: String) {
        state.withLock {
            if !$0.inputFinished { $0.texts.append(text) }
        }
    }

    func finish() {
        state.withLock { $0.inputFinished = true }
    }

    func emitFrame(utteranceIndex: Int) {
        continuation.yield(PocketTTSFrame(samples: [], utteranceIndex: utteranceIndex))
    }

    func endFrames() {
        continuation.finish()
    }

    func cancel() async {
        state.withLock { $0.cancelled = true }
        continuation.finish()
    }
}
