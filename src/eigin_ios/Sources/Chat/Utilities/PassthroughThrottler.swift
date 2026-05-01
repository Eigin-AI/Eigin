import Foundation
import SwiftUI

/// A no-op throttler that transitions phases immediately without a `CADisplayLink`.
///
/// Used for background runs where `CADisplayLink` doesn't fire, which would
/// cause `waitForThrottlerDrain()` to hang indefinitely.
@Observable
@MainActor
final class PassthroughThrottler: StreamThrottling {
    private(set) var phase: StreamThrottler.Phase = .idle
    private(set) var displayedText = ""
    private(set) var fullText = ""
    private(set) var scrollTrigger = 0

    func start() {
        phase = .waiting
    }

    func feed(_ chunk: String) {
        fullText += chunk
        displayedText = fullText
        phase = .streaming
    }

    func finish() {
        displayedText = fullText
        phase = .done
    }

    func abort() {
        phase = .idle
    }

    func reset() {
        resetKeepingPhase(.idle)
    }

    func flushIfStalled() {}

    func resetKeepingPhase(_ targetPhase: StreamThrottler.Phase) {
        phase = targetPhase
        displayedText = ""
        fullText = ""
        scrollTrigger = 0
    }
}
