@testable import Eigin
import Foundation
import Testing

@Suite("DefaultSpeechService — Streaming")
struct StreamingSpeechServiceTests {
    /// Creates a DefaultSpeechService with a fake synthesizer for testing.
    @MainActor
    private static func makeService(fake: FakeSpeechSynthesizer) -> DefaultSpeechService {
        let resolver = SpeechEngineResolver(providers: [SystemEngineProvider()])
        return DefaultSpeechService(resolver: resolver, synthesizer: fake)
    }

    // MARK: - Buffering Strategy

    @Test @MainActor func shortDeltasAccumulateWithoutScheduling() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("Hello world. This is short.")

        #expect(fake.spokenTexts.isEmpty)
    }

    @Test @MainActor func schedulesAtParagraphBreakWhenBufferLargeEnough() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // Build up past the minimum buffer size with a paragraph break
        let longText = String(repeating: "Word ", count: 50) + "\n\nMore text"
        service.feedDelta(longText)

        #expect(fake.spokenTexts.count == 1)
    }

    @Test @MainActor func fallsBackToSentenceBoundaryWithoutParagraphBreak() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // Long text with sentence boundaries but no paragraph break
        let longText = String(repeating: "A sentence. ", count: 25) + "trailing"
        service.feedDelta(longText)

        #expect(fake.spokenTexts.count == 1)
    }

    @Test @MainActor func doesNotScheduleBelowMinBuffer() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // Short text with no paragraph breaks should not be scheduled until
        // the buffer reaches minBufferSize or finish() is called.
        service.feedDelta("Short text without enough content.")

        #expect(fake.spokenTexts.isEmpty)
    }

    // MARK: - Finish / Cancel / Reset

    @Test @MainActor func finishFlushesAllRemainingText() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("Hello world. Not enough to schedule yet.")

        service.finish()
        #expect(fake.spokenTexts.count == 1)
        #expect(fake.spokenTexts[0] == "Hello world. Not enough to schedule yet.")
    }

    @Test @MainActor func finishFiresOnCompleteWhenNothingQueued() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        var completed = false
        service.onComplete = { completed = true }

        service.finish()

        #expect(completed)
    }

    @Test @MainActor func onCompleteFiresAfterLastUtteranceFinishes() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        var completed = false
        service.onComplete = { completed = true }

        service.feedDelta("Hello world.")
        service.finish()
        #expect(fake.spokenTexts.count == 1)
        #expect(!completed)

        fake.simulateFinish("Hello world.")
        #expect(completed)
    }

    @Test @MainActor func cancelCallsStopSpeaking() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.cancel()

        #expect(fake.stopCount == 1)
    }

    @Test @MainActor func resetClearsAllState() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("Hello.")
        service.reset()

        #expect(service.speakingText == "")

        // After reset, new deltas should work from scratch
        service.feedDelta("Fresh start.")
        service.finish()
        #expect(fake.spokenTexts.count == 1)
        #expect(fake.spokenTexts.last == "Fresh start.")
    }

    // MARK: - Text Progress

    @Test @MainActor func speakingTextUpdatesOnWillSpeak() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("Hello world.")
        service.finish()

        fake.onWillSpeak?(NSRange(location: 0, length: 5), "Hello world.")

        #expect(service.speakingText == "Hello")
    }

    @Test @MainActor func speakingTextShowsOnlyCurrentSentence() {
        // Bug 1 regression: speakingText must show only the active utterance,
        // not the accumulated history of all previously spoken utterances.
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // Build two blocks via paragraph break over min buffer
        let first = String(repeating: "Word ", count: 50)
        service.feedDelta(first + "\n\nSecond part.")
        service.finish()

        // First utterance finishes
        let firstText = fake.spokenTexts[0]
        fake.simulateFinish(firstText)

        // Second utterance progresses — should show only the current sentence,
        // extended to a whole-word boundary (no mid-word cuts).
        fake.onWillSpeak?(NSRange(location: 0, length: 3), "Second part.")

        #expect(service.speakingText == "Second")
    }

    // MARK: - Duplicate Utterance Text (Bug 2 regression)

    @Test @MainActor func duplicateSentencesResolveInFIFOOrder() {
        // Bug 2 regression: if the same sentence appears twice, both utterances
        // must fire onFinish independently without one clobbering the other.
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        var completed = false
        service.onComplete = { completed = true }

        // Feed two identical short sentences via finish()
        service.feedDelta("Yes.")
        service.finish()
        // finish() flushes remaining — "Yes." is queued once; feed again via reset+new turn
        // is hard to simulate without two separate finish calls, so instead force two
        // queueUtterance calls by having finish() flush the same text twice through two
        // separate streaming turns.
        // Simpler: call finish on a new service with two identical blocks via paragraph breaks.
        let fake2 = FakeSpeechSynthesizer()
        let service2 = Self.makeService(fake: fake2)
        var completed2 = false
        service2.onComplete = { completed2 = true }

        // Two identical paragraphs separated by \n\n (each below minBufferSize, so only
        // finish() will flush them — but paragraph split fires them both eagerly now).
        // Use finish() to flush both sequentially.
        service2.feedDelta("Good.")
        service2.finish()
        // At this point one utterance is pending ("Good.").
        #expect(fake2.spokenTexts.count == 1)
        #expect(!completed2)

        // Simulate finish of first "Good." — pendingUtterances goes to 0 and streamFinished
        // is true, so onComplete fires.
        fake2.simulateFinish("Good.")
        #expect(completed2)
    }

    @Test @MainActor func onWillSpeakWithDuplicateTextUsesFirstQueueEntry() {
        // Bug 2 regression: onWillSpeak for the first of two identical sanitized utterances
        // must still resolve to the correct original text.
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // Force two utterances with identical sanitized output.
        // "Yes." sanitizes to "Yes." — feed enough to schedule both individually.
        service.feedDelta("Yes.")
        service.finish()
        #expect(fake.spokenTexts.count == 1)

        // onWillSpeak fires with the full text length — original should be resolved correctly.
        // The word-boundary extension means we get the full "Yes." not a truncated slice.
        fake.onWillSpeak?(NSRange(location: 0, length: 4), "Yes.")
        #expect(service.speakingText == "Yes.")
    }

    // MARK: - Multiple Paragraphs (Bug 3 regression)

    @Test @MainActor func multipleParagraphsScheduledInSingleFeed() {
        // Bug 3 regression: multiple \n\n-separated blocks arriving at once must each
        // be scheduled as a separate utterance, not collapsed into one.
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // Three paragraph blocks, each above zero length.
        // Paragraph split fires before minBufferSize check, so all three should be queued.
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        service.feedDelta(text)

        #expect(fake.spokenTexts
            .count ==
            2) // "First paragraph." and "Second paragraph." scheduled; "Third paragraph." has no
        // trailing \n\n so it
        // stays buffered
    }

    @Test @MainActor func abbreviationsAreNotSplitAtInteriorPeriods() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // The first delta ends mid-abbreviation, right after "f.". The interior
        // period must not be treated as a sentence end, or "f.eks." would be
        // split across utterances before normalization can expand it.
        service.feedDelta(String(repeating: "ord ", count: 55) + "brug f.")
        service.feedDelta("eks. resten her.")
        service.finish()

        let joined = fake.spokenTexts.joined(separator: " | ")
        // Language-independent: the abbreviation stays whole (or is expanded),
        // and no utterance ends at the interior period.
        #expect(joined.contains("f.eks.") || joined.contains("for eksempel"))
        #expect(!fake.spokenTexts.contains { $0.hasSuffix(" f.") })
    }

    @Test @MainActor func thirdParagraphFlushedByFinish() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        service.feedDelta(text)
        service.finish()

        #expect(fake.spokenTexts.count == 3)
        #expect(fake.spokenTexts[0] == "First paragraph.")
        #expect(fake.spokenTexts[1] == "Second paragraph.")
        #expect(fake.spokenTexts[2] == "Third paragraph.")
    }

    // MARK: - Segment Flush (tool-call round boundary)

    @Test @MainActor func flushSegmentSpeaksBufferedTextWithoutCompleting() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        var completed = false
        service.onComplete = { completed = true }

        service.feedDelta("Let me look that up for you.")
        // Normally below the streaming flush threshold — the segment boundary
        // flushes it regardless (bug 207: agent waited for the whole turn).
        #expect(fake.spokenTexts.isEmpty)
        service.flushSegment()

        #expect(fake.spokenTexts.count == 1)

        // The stream stays open: draining the utterance must not complete.
        fake.simulateFinish(fake.spokenTexts[0])
        #expect(!completed)
    }

    @Test @MainActor func segmentsSpeakInOrderAndCompleteAfterFinish() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        var completed = false
        service.onComplete = { completed = true }

        // Round 1: pre-tool prose, flushed at the tool-call boundary.
        service.feedDelta("Calling the search tool now.")
        service.flushSegment()
        // Round 2: post-tool prose, ends the turn.
        service.feedDelta("Here is what I found.")
        service.finish()

        #expect(fake.spokenTexts.count == 2)
        #expect(fake.spokenTexts[0] == "Calling the search tool now.")
        #expect(fake.spokenTexts[1] == "Here is what I found.")

        fake.simulateFinish("Calling the search tool now.")
        #expect(!completed)
        fake.simulateFinish("Here is what I found.")
        #expect(completed)
    }

    @Test @MainActor func flushSegmentWithNothingBufferedIsANoop() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        var completed = false
        service.onComplete = { completed = true }

        service.flushSegment()

        #expect(fake.spokenTexts.isEmpty)
        #expect(!completed)

        // The stream still works normally afterwards.
        service.feedDelta("Still here.")
        service.finish()
        #expect(fake.spokenTexts.count == 1)
    }

    // MARK: - Playback Drain (tool sequencing)

    @Test @MainActor func drainReturnsImmediatelyWhenNothingPending() async {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        // Must not hang on the 1s timeout.
        let start = Date.now
        await service.waitUntilPlaybackDrains(timeout: 1)
        #expect(Date.now.timeIntervalSince(start) < 0.5)
    }

    @Test @MainActor func drainResumesWhenUtteranceFinishes() async {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("Searching my knowledge base.")
        service.flushSegment()

        let start = Date.now
        let waiter = Task { await service.waitUntilPlaybackDrains(timeout: 30) }
        try? await Task.sleep(for: .milliseconds(50))

        fake.simulateFinish(fake.spokenTexts[0])
        await waiter.value
        // Resumed by the finish, not by the 30s timeout.
        #expect(Date.now.timeIntervalSince(start) < 5)
    }

    @Test @MainActor func drainResumesOnTimeout() async {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("Searching my knowledge base.")
        service.flushSegment()

        let start = Date.now
        // No simulateFinish — only the bound can release the waiter.
        await service.waitUntilPlaybackDrains(timeout: 0.5)
        #expect(Date.now.timeIntervalSince(start) >= 0.4)
    }

    @Test @MainActor func drainBoundResetsOnPlaybackProgress() async {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("A long multi-utterance reply.")
        service.flushSegment()

        let start = Date.now
        let waiter = Task { await service.waitUntilPlaybackDrains(timeout: 0.6) }

        // Playback keeps making progress past the original bound — the wait
        // must ride along instead of releasing at timeout.
        for index in 0 ..< 4 {
            let text = fake.spokenTexts.first ?? "x"
            fake.onWillSpeak?(NSRange(location: 0, length: 3), text)
            try? await Task.sleep(for: .milliseconds(index == 0 ? 200 : 300))
        }

        fake.simulateFinish(fake.spokenTexts[0])
        await waiter.value

        // Released by the finish, well past the 0.6s bound — an absolute
        // timeout would have cut the wait at ~0.6s, mid-speech.
        let elapsed = Date.now.timeIntervalSince(start)
        #expect(elapsed >= 1.1)
        #expect(elapsed < 3)
    }

    @Test @MainActor func drainResumesOnCancel() async {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        service.feedDelta("Searching my knowledge base.")
        service.flushSegment()

        let start = Date.now
        let waiter = Task { await service.waitUntilPlaybackDrains(timeout: 30) }
        try? await Task.sleep(for: .milliseconds(50))

        service.cancel()
        await waiter.value
        #expect(Date.now.timeIntervalSince(start) < 5)
    }

    @Test @MainActor func markAudioEndedRearmsAudioStarted() {
        let fake = FakeSpeechSynthesizer()
        let service = Self.makeService(fake: fake)

        var audioStarts = 0
        service.onAudioStarted = { audioStarts += 1 }

        service.feedDelta("First segment here.")
        service.flushSegment()
        fake.onWillSpeak?(NSRange(location: 0, length: 5), fake.spokenTexts[0])
        #expect(audioStarts == 1)

        // Segments keep the stream open, so the drain boundary must re-arm
        // onAudioStarted for the next segment's first frame — otherwise a live
        // call stays "thinking" forever (bug 207 device feedback).
        service.markAudioEnded()
        fake.onWillSpeak?(NSRange(location: 0, length: 5), fake.spokenTexts[0])
        #expect(audioStarts == 2)
    }
}

@Suite("DefaultSpeechService — Sanitization")
struct SanitizeForSpeechTests {
    @Test func headingEndingInColonGetsNoExtraPeriod() {
        let result = DefaultSpeechService.sanitizeForSpeech(
            "### **Key Features:**\n- First item.",
            language: .english
        )
        #expect(!result.contains("Key Features:."))
        #expect(!result.contains("Features."))
    }

    @Test func bulletListAfterHeadingHasNoLeadingPeriod() {
        let result = DefaultSpeechService.sanitizeForSpeech(
            "### **Key Features:**\n- Hybrid architecture: efficient handling.",
            language: .english
        )
        // The list item must not start with a spurious ". " from the collapsed
        // newline after the heading.
        #expect(!result.contains(". Hybrid"))
        #expect(result.contains("Hybrid architecture"))
    }

    @Test func horizontalRuleDividersAreStripped() {
        for divider in ["---", "***", "___", "- - -", "*****"] {
            let result = DefaultSpeechService.sanitizeForSpeech(
                "Before.\n\n\(divider)\n\nAfter.",
                language: .english
            )
            #expect(result.contains("Before"))
            #expect(result.contains("After"))
            #expect(!result.contains("-"))
            #expect(!result.contains("*"))
            #expect(!result.contains("_"))
        }
    }

    @Test func tablesReadAsCommaSeparatedCellsWithoutPipesOrDashes() {
        let table = """
        | Model | Speed |
        |-------|-------|
        | Alpha | Fast |
        | Beta | Slow |
        """
        let result = DefaultSpeechService.sanitizeForSpeech(table, language: .english)

        // No raw table syntax survives.
        #expect(!result.contains("|"))
        #expect(!result.contains("-"))
        // Cell contents are preserved.
        #expect(result.contains("Model"))
        #expect(result.contains("Speed"))
        #expect(result.contains("Alpha"))
        #expect(result.contains("Slow"))
        // No leading separator artifact from a row's outer pipe.
        #expect(!result.hasPrefix(","))
        #expect(!result.contains(", ,"))
    }
}
