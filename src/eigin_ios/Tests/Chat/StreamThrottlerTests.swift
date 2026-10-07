@testable import Eigin
import Testing

@Suite("StreamThrottler.wholeWords")
@MainActor
struct StreamThrottlerTests {
    private func wholeWords(_ text: String) -> String? {
        StreamThrottler.wholeWords(text[...]).map(String.init)
    }

    @Test func trimsBackToLastCompletedWord() {
        #expect(wholeWords("hello wor") == "hello ")
    }

    @Test func keepsTextAlreadyEndingAtWhitespace() {
        #expect(wholeWords("hello ") == "hello ")
    }

    @Test func returnsNilWhenNoWordCompletedYet() {
        #expect(wholeWords("hello") == nil)
    }

    @Test func treatsNewlineAsWordBoundary() {
        #expect(wholeWords("line one\nlin") == "line one\n")
    }

    @Test func trimsToTheLastOfConsecutiveSpaces() {
        #expect(wholeWords("one two   thre") == "one two   ")
    }
}

@Suite("StreamThrottler streaming and tail reveal")
@MainActor
struct StreamThrottlerTailRevealTests {
    /// Mutable fake clock so tests control both `now()` and tick timestamps.
    private final class Clock: @unchecked Sendable {
        var time: TimeInterval = 0
    }

    private func makeThrottler(clock: Clock, stallGrace: TimeInterval = 0.45) -> StreamThrottler {
        // High catch-up rate so a single tick exhausts the buffer.
        StreamThrottler(
            catchUpRate: 100,
            stallGrace: stallGrace,
            now: { clock.time }
        )
    }

    @Test func revealsWholeWordsBeforeGraceElapses() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("hello wor")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)

        #expect(throttler.displayedText == "hello ")
    }

    @Test func revealsTrailingPartialWordAfterStallGrace() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("hello wor")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)
        clock.time = 0.5
        throttler.tick(timestamp: 0.5)

        #expect(throttler.displayedText == "hello wor")
    }

    @Test func finishFlushesBufferedTailOnNextTick() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("hello wor")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)
        #expect(throttler.displayedText == "hello ")

        throttler.finish()
        throttler.tick(timestamp: 0.15)

        #expect(throttler.displayedText == "hello wor")
        #expect(throttler.phase == .done)
    }

    @Test func feedingAfterStallRevealResumesWholeWordPace() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("hello wor")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)
        clock.time = 0.5
        throttler.tick(timestamp: 0.5)
        #expect(throttler.displayedText == "hello wor")

        // Stream resumes mid-word: the joined word shows once complete.
        throttler.feed("ld there")
        clock.time = 0.6
        throttler.tick(timestamp: 0.6)

        #expect(throttler.displayedText == "hello world ")
    }
}

@Suite("StreamThrottler catch-up flag")
@MainActor
struct StreamThrottlerCaughtUpTests {
    private final class Clock: @unchecked Sendable {
        var time: TimeInterval = 0
    }

    private func makeThrottler(clock: Clock) -> StreamThrottler {
        StreamThrottler(
            catchUpRate: 100,
            stallGrace: 0.45,
            now: { clock.time }
        )
    }

    @Test func notCaughtUpWhileTypewriterBehind() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("unrevealed buffer of text")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)

        #expect(!throttler.hasCaughtUp)
    }

    @Test func caughtUpOnceQuietWithEverythingDisplayed() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("hello world")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)
        #expect(throttler.displayedText == "hello ")

        // Past the stall grace with everything revealed.
        clock.time = 0.6
        throttler.tick(timestamp: 0.6)

        #expect(throttler.hasCaughtUp)
    }

    @Test func newFeedBreaksCaughtUp() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("hello world")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)
        clock.time = 0.6
        throttler.tick(timestamp: 0.6)
        #expect(throttler.hasCaughtUp)

        throttler.feed(" again")

        #expect(!throttler.hasCaughtUp)
    }

    @Test func resetClearsCaughtUp() {
        let clock = Clock()
        let throttler = makeThrottler(clock: clock)

        throttler.feed("hello world")
        clock.time = 0.1
        throttler.tick(timestamp: 0.1)
        clock.time = 0.6
        throttler.tick(timestamp: 0.6)
        #expect(throttler.hasCaughtUp)

        throttler.reset()

        #expect(!throttler.hasCaughtUp)
    }
}
