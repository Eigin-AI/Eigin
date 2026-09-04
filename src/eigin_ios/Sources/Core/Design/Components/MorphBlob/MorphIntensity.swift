import SwiftUI

/// How much of the morph choreography is showing: 0 sits still on the resting
/// circle, 1 runs the full wobble. The value is a pure function of time since
/// the state last changed, ramping over `Animations.slow` (0.4s) — so phase
/// changes blend into the wobble instead of snapping.
///
/// Like the rest of the blob, nothing is stored: any frame in time resolves
/// to exactly one shape.
struct MorphIntensity: Equatable {
    /// Whether the blob should be morphing.
    let engaged: Bool
    /// When the state last changed — anchors the ramp.
    let changedAt: Date
    /// The value showing at the moment of the change — where the ramp
    /// starts. Ramping out from a mid-flight value keeps transitions
    /// continuous, e.g. leaving listening (already a full circle) never
    /// bounces through the wobble.
    let start: Double

    init(engaged: Bool, changedAt: Date, start: Double? = nil) {
        self.engaged = engaged
        self.changedAt = changedAt
        self.start = start ?? (engaged ? 0 : 1)
    }

    /// Fully engaged for the whole of time (the chat indicator's mode).
    static let full = MorphIntensity(engaged: true, changedAt: .distantPast, start: 1)
    /// Never engaged for the whole of time.
    static let none = MorphIntensity(engaged: false, changedAt: .distantPast, start: 0)

    /// A new state anchored at `change`, resuming from whatever value this
    /// one is showing right now.
    func transitioned(to engaged: Bool, at change: Date) -> MorphIntensity {
        MorphIntensity(engaged: engaged, changedAt: change, start: value(at: change))
    }

    func value(at date: Date) -> Double {
        let target = engaged ? 1.0 : 0.0
        let elapsed = date.timeIntervalSince(changedAt)
        // Snap the settled ends — date arithmetic can land a hair inside the
        // ramp, and the curve is flat there so the wobbliness stays invisible.
        if elapsed >= Animations.slow - 1e-6 { return target }
        if elapsed <= 0 { return start }
        let progress = min(max(elapsed / Animations.slow, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        return start + (target - start) * eased
    }
}
