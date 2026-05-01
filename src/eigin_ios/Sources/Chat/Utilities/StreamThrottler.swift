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
    private var displayLink: CADisplayLink?
    private var serverDone = false
    private var tickCount = 0
    private let scrollEvery = 6 // scroll at ~10Hz instead of 60Hz

    /// Fraction of the pending gap consumed each display-link tick (60 fps).
    /// Higher = faster catch-up, less perceived lag. Range: 0.03 (slow) – 0.15 (fast).
    private let catchUpRate: Double

    init(catchUpRate: Double = 0.05) {
        self.catchUpRate = catchUpRate
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
        scrollTrigger = 0
        serverDone = false
        tickCount = 0
    }

    // MARK: - Display Link

    private func startTimer() {
        let trampoline = DisplayLinkTrampoline { [weak self] in
            self?.tick()
        }
        let link = CADisplayLink(
            target: trampoline, selector: #selector(DisplayLinkTrampoline.tick)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        let distance = inputCount - displayedCount
        guard distance > 0 else {
            if serverDone { completeDisplay() }
            return
        }

        let advance = max(1, Int(round(Double(distance) * catchUpRate)))
        displayedCount = min(displayedCount + advance, inputCount)
        displayedText = String(fullText.prefix(displayedCount))

        tickCount += 1
        if tickCount % scrollEvery == 0 {
            scrollTrigger += 1
        }

        if serverDone, displayedCount >= inputCount {
            completeDisplay()
        }
    }

    private func completeDisplay() {
        stopTimer()
        // Guard redundant text update to avoid two layout passes in one frame
        // (tick may have already set displayedText to the final value).
        if displayedText != fullText {
            displayedText = fullText
        }
        displayedCount = inputCount
        phase = .done
    }
}

// MARK: - CADisplayLink trampoline

private final class DisplayLinkTrampoline: @unchecked Sendable {
    let action: @MainActor () -> Void
    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func tick() {
        // CADisplayLink always fires on the main thread, so this is safe.
        MainActor.assumeIsolated { [action] in action() }
    }
}
