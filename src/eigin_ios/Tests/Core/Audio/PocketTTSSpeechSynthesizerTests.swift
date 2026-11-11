@testable import Eigin
import Foundation
import Testing

@Suite("PocketTTS generation lifecycle")
@MainActor
struct PocketTTSSpeechSynthesizerTests {
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        return condition()
    }

    @Test func textAfterFinishUsesAnotherSession() async {
        let first = FakePocketTTSSession()
        let second = FakePocketTTSSession()
        var requests = 0
        let synth = PocketTTSSpeechSynthesizer(makeSession: {
            requests += 1
            return requests == 1 ? first : second
        }, audioEnabled: false)
        defer { synth.stopSpeaking() }
        var completed: [String] = []
        synth.onFinish = { completed.append($0) }

        synth.speak("Before the tool.")
        #expect(await waitUntil { first.texts.count == 1 })
        synth.finishSpeaking()
        #expect(first.inputFinished)

        // The tool returns before the preceding session's audio has drained.
        synth.speak("The final answer.")
        synth.finishSpeaking()
        first.endFrames()

        #expect(await waitUntil { second.texts == ["The final answer."] })
        #expect(second.inputFinished)
        second.endFrames()
        #expect(await waitUntil { completed.count == 2 })
        #expect(completed == ["Before the tool.", "The final answer."])
        #expect(requests == 2)
    }

    @Test func cancelledStartupCannotConsumeNextTurnsText() async {
        let stale = FakePocketTTSSession()
        let current = FakePocketTTSSession()
        var creation: CheckedContinuation<any PocketTTSSession, Never>?
        var requests = 0
        let synth = PocketTTSSpeechSynthesizer(makeSession: {
            requests += 1
            if requests == 1 {
                return await withCheckedContinuation { creation = $0 }
            }
            return current
        }, audioEnabled: false)
        defer { synth.stopSpeaking() }
        var completed: [String] = []
        synth.onFinish = { completed.append($0) }

        synth.speak("Interrupted turn.")
        #expect(await waitUntil { creation != nil })
        synth.stopSpeaking()
        synth.speak("New turn.")
        synth.finishSpeaking()
        creation?.resume(returning: stale)
        // Also let a broken implementation's stale stream exit to avoid hanging.
        stale.endFrames()

        #expect(await waitUntil { current.texts == ["New turn."] })
        #expect(stale.texts.isEmpty)
        #expect(stale.cancelled)
        #expect(current.inputFinished)
        current.endFrames()
        #expect(await waitUntil { completed == ["New turn."] })
        #expect(requests == 2)
    }

    @Test func oldTaskExitDoesNotStartDuplicateGeneration() async {
        let stale = FakePocketTTSSession()
        let current = FakePocketTTSSession()
        var oldCreation: CheckedContinuation<any PocketTTSSession, Never>?
        var newCreation: CheckedContinuation<any PocketTTSSession, Never>?
        var requests = 0
        let synth = PocketTTSSpeechSynthesizer(makeSession: {
            requests += 1
            if requests == 1 {
                return await withCheckedContinuation { oldCreation = $0 }
            }
            if requests == 2 {
                return await withCheckedContinuation { newCreation = $0 }
            }
            return current
        }, audioEnabled: false)
        defer { synth.stopSpeaking() }

        synth.speak("Old turn.")
        #expect(await waitUntil { oldCreation != nil })
        synth.stopSpeaking()
        synth.speak("First chunk.")
        oldCreation?.resume(returning: stale)
        stale.endFrames()
        #expect(await waitUntil { newCreation != nil })

        // Older cleanup must leave the new startup active while it is suspended.
        synth.speak("Second chunk.")
        synth.finishSpeaking()
        newCreation?.resume(returning: current)
        #expect(await waitUntil { current.inputFinished })
        #expect(current.texts == ["First chunk.", "Second chunk."])
        #expect(requests == 2)
        current.endFrames()
    }

    @Test func streamingChunksShareAnOpenSession() async {
        let session = FakePocketTTSSession()
        var requests = 0
        let synth = PocketTTSSpeechSynthesizer(makeSession: {
            requests += 1
            return session
        }, audioEnabled: false)
        defer { synth.stopSpeaking() }
        var completed: [String] = []
        synth.onFinish = { completed.append($0) }

        synth.speak("First chunk.")
        #expect(await waitUntil { session.texts.count == 1 })
        synth.speak("Second chunk.")
        synth.finishSpeaking()
        #expect(session.texts == ["First chunk.", "Second chunk."])
        session.emitFrame(utteranceIndex: 0)
        session.emitFrame(utteranceIndex: 1)
        #expect(await waitUntil { completed == ["First chunk."] })
        session.endFrames()
        #expect(await waitUntil { completed.count == 2 })
        #expect(completed == ["First chunk.", "Second chunk."])
        #expect(requests == 1)
    }

    @Test func completionCanQueueMoreSpeechWithoutLosingIt() async {
        let first = FakePocketTTSSession()
        let second = FakePocketTTSSession()
        var requests = 0
        let synth = PocketTTSSpeechSynthesizer(makeSession: {
            requests += 1
            return requests == 1 ? first : second
        }, audioEnabled: false)
        defer { synth.stopSpeaking() }
        var completed: [String] = []
        synth.onFinish = { [weak synth] text in
            completed.append(text)
            if completed.count == 1 {
                synth?.speak("Next answer.")
                synth?.finishSpeaking()
            }
        }

        synth.speak("First answer.")
        synth.finishSpeaking()
        #expect(await waitUntil { first.inputFinished })
        first.endFrames()
        #expect(await waitUntil { second.inputFinished })
        #expect(second.texts == ["Next answer."])
        second.endFrames()
        #expect(await waitUntil { completed == ["First answer.", "Next answer."] })
        #expect(requests == 2)
    }

    @Test func finishBeforeSessionCreationFlushesTextOnce() async {
        let session = FakePocketTTSSession()
        var creation: CheckedContinuation<any PocketTTSSession, Never>?
        let synth = PocketTTSSpeechSynthesizer(makeSession: {
            await withCheckedContinuation { creation = $0 }
        }, audioEnabled: false)
        defer { synth.stopSpeaking() }
        var completed: [String] = []
        synth.onFinish = { completed.append($0) }

        synth.speak("A buffered answer.")
        synth.finishSpeaking()
        #expect(await waitUntil { creation != nil })
        creation?.resume(returning: session)
        #expect(await waitUntil { session.inputFinished })
        #expect(session.texts == ["A buffered answer."])
        session.endFrames()
        #expect(await waitUntil { completed == ["A buffered answer."] })
    }
}
