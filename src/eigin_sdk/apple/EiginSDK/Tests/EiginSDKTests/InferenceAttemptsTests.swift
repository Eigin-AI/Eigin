import EiginSDK
import Testing

@Suite("Experimental inference attempt bindings")
struct InferenceAttemptsTests {
    @Test func replacementWinsAndLatePrimaryCannotFinishItsStream() {
        let attempts = EiginSDK.Experimental.Inference.Attempts(
            local: false, routed: true, maxBufferedBytes: 1024, startingModel: "A"
        )
        #expect(attempts.step(observation: .start(hedgeDelayMs: nil, ceilingMs: 10000)) == [.open(id: 0)])
        #expect(attempts.step(observation: .ended(id: 0)) == [.chase(failed: 0, replacement: 2, timeout: false)])
        #expect(attempts.claimSwitch(chase: 2, from: "A", to: "B"))
        attempts.replacementOpened(model: "B")
        #expect(attempts.step(observation: .opened(id: 2)).last == .forward(id: 2))
        #expect(attempts.step(observation: .event(id: 2, kind: .content(nonempty: true), bytes: 1)) == [.win(id: 2), .deliver])
        attempts.selected(model: "B")
        #expect(attempts.retryWon())
        #expect(attempts.step(observation: .ended(id: 0)).isEmpty)
        #expect(attempts.step(observation: .ended(id: 2)) == [.finish(errorSource: 2, timeout: false)])
    }

    @Test func silentRequestWakesToDispatchTheHedge() async {
        let attempts = EiginSDK.Experimental.Inference.Attempts(local: false, routed: true, maxBufferedBytes: 10, startingModel: "A")
        _ = attempts.step(observation: .start(hedgeDelayMs: 5, ceilingMs: 60000))
        #expect(await attempts.waitForDeadline())
        #expect(attempts.drainDeadline() == [.open(id: 1)])
        _ = attempts.step(observation: .cancel)
        #expect(attempts.drainDeadline().isEmpty)
    }
}
