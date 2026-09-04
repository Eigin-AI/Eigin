import Foundation
import QuartzCore
import SwiftUI

@MainActor
protocol StreamThrottling: AnyObject {
    var phase: StreamThrottler.Phase { get }
    var displayedText: String { get }
    var fullText: String { get }
    var scrollTrigger: Int { get }
    func start()
    func feed(_ chunk: String)
    func finish()
    func abort()
    func reset()
    func resetKeepingPhase(_ targetPhase: StreamThrottler.Phase)
    func flushIfStalled()
}

@Observable
@MainActor
final class StreamThrottler: StreamThrottling {
    enum Phase: Equatable {
        case idle
        case waiting
        case streaming
        case done
    }

    private(set) var phase: Phase = .idle
    private(set) var displayedText = ""
    private(set) var fullText = ""
    private(set) var scrollTrigger = 0

    private var inputCount = 0
    private var displayedCount = 0
    /// Monotonic catch-up cursor (characters). Advances every tick regardless of word
    /// boundaries; `displayedCount` snaps back to the last whole word at or under it.
    /// Separating them keeps the display word-aligned while the cursor still always
    /// reaches `inputCount`, so the drain can't stall on a trailing partial word.
    private var scanCount = 0
    private var displayLink: CADisplayLink?
    private var serverDone = false
    private var tickCount = 0
    private let scrollEvery = 6 // scroll every 6 published words
    /// Timestamp of the previous tick, used to scale catch-up by real elapsed time.
    /// Zero means "no prior tick yet" (first tick assumes the nominal interval).
    private var lastTickTime: CFTimeInterval = 0

    /// Maximum tick rate for the display link. Publishing a few words per second
    /// doesn't need full refresh-rate fidelity, so cap it to save work per frame.
    private let maxFrameRate: Float = 30

    /// Continuous catch-up coefficient, per second: each tick closes `1 - exp(-rate · dt)`
    /// of the gap to the buffered text, where `dt` is the real elapsed time since the last
    /// tick. Scaling by `dt` keeps reveal speed independent of refresh rate and tick
    /// cadence. Higher = faster catch-up and larger word chunks per tick.
    private let catchUpRate: Double

    /// How long the stream may sit quiet with all buffered input already scanned
    /// before the tail — even a trailing partial word — is revealed. Slow models
    /// often deliver their final deltas seconds before the finish event; without
    /// this grace the last word hides for that entire window.
    private let stallGrace: TimeInterval

    /// Injected clock, in the same timebase as ``CADisplayLink`` timestamps.
    private let now: () -> TimeInterval

    /// Timestamp of the most recent `feed()`, used for the stall check.
    private var lastFeedTime: TimeInterval = 0

    init(
        catchUpRate: Double = 2.0,
        stallGrace: TimeInterval = 0.45,
        now: @escaping () -> TimeInterval = CACurrentMediaTime
    ) {
        self.catchUpRate = catchUpRate
        self.stallGrace = stallGrace
        self.now = now
    }

    func start() {
        reset()
        phase = .waiting
    }

    func feed(_ chunk: String) {
        if phase == .waiting {
            phase = .streaming
            startTimer()
        }
        fullText += chunk
        inputCount += chunk.count
        lastFeedTime = now()
    }

    func finish() {
        serverDone = true
        if displayedCount >= inputCount {
            completeDisplay()
        }
    }

    /// Immediately completes display if the server is done but the display link
    /// has stalled (e.g. app is in background where CADisplayLink stops firing).
    /// Only call this when the app is backgrounded — on-screen it would skip
    /// the typing animation.
    func flushIfStalled() {
        guard serverDone, phase == .streaming else { return }
        completeDisplay()
    }

    func abort() {
        stopTimer()
        phase = .idle
    }

    func reset() {
        resetKeepingPhase(.idle)
    }

    /// Resets text buffers but transitions to the given phase instead of `.idle`.
    /// Use `.waiting` between tool-call rounds to keep the typing indicator visible.
    func resetKeepingPhase(_ targetPhase: Phase) {
        stopTimer()
        phase = targetPhase
        displayedText = ""
        fullText = ""
        inputCount = 0
        displayedCount = 0
        scanCount = 0
        scrollTrigger = 0
        serverDone = false
        tickCount = 0
        lastFeedTime = 0
    }

    // MARK: - Display Link

    private func startTimer() {
        lastTickTime = 0
        let trampoline = DisplayLinkTrampoline { [weak self] timestamp in
            self?.tick(timestamp: timestamp)
        }
        let link = CADisplayLink(
            target: trampoline, selector: #selector(DisplayLinkTrampoline.tick(_:))
        )
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 15, maximum: maxFrameRate, preferred: maxFrameRate
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Driven by the display link; internal so tests can step time manually.
    func tick(timestamp: CFTimeInterval) {
        // Real elapsed time since the last tick. Falls back to the nominal interval
        // on the first tick (when there's no previous timestamp to diff against).
        let dt = lastTickTime > 0 ? max(0, timestamp - lastTickTime) : 1 / Double(maxFrameRate)
        lastTickTime = timestamp

        let distance = inputCount - scanCount
        guard distance > 0 else {
            if serverDone {
                completeDisplay()
            } else if inputCount > displayedCount,
                      now() - lastFeedTime >= stallGrace
            {
                revealStalledTail()
            }
            return
        }

        // Advance the catch-up cursor by a time-scaled fraction of the gap, so reveal
        // speed is the same regardless of how often this fires or the display's
        // refresh rate. `scanCount` always moves toward `inputCount` and never parks.
        let fraction = 1 - exp(-catchUpRate * dt)
        let advance = max(1, Int(round(Double(distance) * fraction)))
        scanCount = min(scanCount + advance, inputCount)
        let candidate = fullText.prefix(scanCount)

        let revealed: Substring
        if serverDone, scanCount >= inputCount {
            // Nothing more is coming and the cursor has reached the end: reveal
            // everything, including the final (possibly partial) word.
            revealed = candidate
        } else if let words = Self.wholeWords(candidate) {
            // Otherwise reveal only completed words, so line-breaking never reflows
            // a half-typed word.
            revealed = words
        } else {
            // No completed word in range yet — wait for the cursor to advance.
            return
        }

        let newCount = revealed.count
        guard newCount > displayedCount else { return }
        displayedCount = newCount
        displayedText = String(revealed)

        tickCount += 1
        if tickCount % scrollEvery == 0 {
            scrollTrigger += 1
        }

        if serverDone, displayedCount >= inputCount {
            completeDisplay()
        }
    }

    /// Reveals everything buffered, including any partial trailing word.
    /// Runs when the cursor has caught up but the stream has been quiet for
    /// `stallGrace`: the word is fully received, so hiding it reads as a hang.
    private func revealStalledTail() {
        scanCount = inputCount
        displayedCount = inputCount
        displayedText = fullText
    }

    /// Trims a streamed prefix back to the last completed word so we never reveal a
    /// half-typed word. Returns `nil` when no whole word is available yet.
    static func wholeWords(_ candidate: Substring) -> Substring? {
        guard let lastSpace = candidate.lastIndex(where: \.isWhitespace) else { return nil }
        return candidate[...lastSpace]
    }

    private func completeDisplay() {
        stopTimer()
        // Guard redundant text update to avoid two layout passes in one frame
        // (tick may have already set displayedText to the final value).
        if displayedText != fullText {
            displayedText = fullText
        }
        displayedCount = inputCount
        scanCount = inputCount
        phase = .done
    }
}

// MARK: - CADisplayLink trampoline

private final class DisplayLinkTrampoline: @unchecked Sendable {
    let action: @MainActor (CFTimeInterval) -> Void
    init(action: @escaping @MainActor (CFTimeInterval) -> Void) {
        self.action = action
    }

    @objc func tick(_ link: CADisplayLink) {
        // CADisplayLink always fires on the main thread, so this is safe. Read the
        // (Sendable) timestamp here so the non-Sendable link never crosses isolation.
        let timestamp = link.timestamp
        MainActor.assumeIsolated { [action] in action(timestamp) }
    }
}
