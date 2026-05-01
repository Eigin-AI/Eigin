import Foundation
import QuartzCore

/// Smoothly chases a target progress value at a capped speed.
///
/// Rather than jumping the UI progress bar to each reported value,
/// `ChasingProgress` advances its `value` toward `target` at most
/// `maxSpeed` units per second (driven by a ~10 fps timer). SwiftUI
/// animations between ticks handle the rest of the smoothing.
@MainActor @Observable
final class ChasingProgress {
    /// Current display value (0–1). Bind your progress bar to this.
    private(set) var value: Float = 0

    /// True only after `target` reached 1.0 **and** `value` caught up (>= 0.99).
    private(set) var isFinished: Bool = false

    private var target: Float = 0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private let maxSpeed: Float

    init(maxSpeed: Float = 0.7) {
        self.maxSpeed = maxSpeed
    }

    /// Set a new target for the display value to chase. Clamped to 0…1.
    func setTarget(_ t: Float) {
        target = min(max(t, 0), 1)
        startDisplayLinkIfNeeded()
    }

    /// Stop the display link and reset all state to zero.
    func reset() {
        stopDisplayLink()
        value = 0
        target = 0
        isFinished = false
    }

    // MARK: - Private

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 10)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt: Float = if lastTimestamp == 0 {
            1.0 / 10.0 // assume ~10fps for the first frame
        } else {
            Float(link.timestamp - lastTimestamp)
        }
        lastTimestamp = link.timestamp

        let step = maxSpeed * dt
        let remaining = target - value

        if remaining <= 0 {
            value = target
        } else {
            value += min(step, remaining)
        }

        if value >= 0.99, target >= 1.0 {
            isFinished = true
            stopDisplayLink()
        }
    }
}
