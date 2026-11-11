import Foundation

/// Inference boundary used by PocketTTS speech playback.
protocol PocketTTSSession: Sendable {
    var frames: AsyncThrowingStream<PocketTTSFrame, Error> { get }
    func enqueue(_ text: String)
    func finish()
    func cancel() async
}

/// Generated audio with its position in the session's text queue.
struct PocketTTSFrame: Sendable {
    let samples: [Float]
    let utteranceIndex: Int?
}

#if !targetEnvironment(simulator)
import FluidAudio

/// Adapts FluidAudio's frame stream to the speech playback boundary.
final class FluidPocketTTSSession: PocketTTSSession, Sendable {
    let frames: AsyncThrowingStream<PocketTTSFrame, Error>
    private let session: PocketTtsSession

    init(session: PocketTtsSession) {
        self.session = session
        frames = AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await frame in session.frames {
                        continuation.yield(PocketTTSFrame(
                            samples: frame.samples,
                            utteranceIndex: frame.utteranceIndex
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func enqueue(_ text: String) {
        session.enqueue(text)
    }

    func finish() {
        session.finish()
    }

    func cancel() async {
        await session.cancel()
    }
}

extension PocketTTSSpeechSynthesizer {
    convenience init(modelManager: PocketTTSModelManager, voiceName: String = "alba") {
        self.init(
            makeSession: {
                try await modelManager.load()
                try Task.checkCancellation()
                guard let manager = modelManager.manager else {
                    throw CancellationError()
                }
                let session = try await manager.makeSession(voice: voiceName)
                return FluidPocketTTSSession(session: session)
            },
            prepare: { try? await modelManager.load() },
            scheduleUnload: { modelManager.scheduleUnload() }
        )
    }
}
#endif
