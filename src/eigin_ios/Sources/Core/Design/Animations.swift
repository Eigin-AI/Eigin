import SwiftUI

/// App-wide animation presets, providing consistent motion across all views.
///
/// Three speed tiers cover most UI needs. Each comes as both
/// a duration (for manual use) and a pre-built `Animation` value.
enum Animations {
    // MARK: - Durations

    /// 0.15s — Instant feedback: button highlights, toggle flips, icon swaps.
    static let fast: Double = 0.15

    /// 0.25s — Standard transitions: reveals, slides, size changes.
    static let normal: Double = 0.25

    /// 0.4s — Deliberate motion: view transitions, modals, onboarding.
    static let slow: Double = 0.4

    // MARK: - Presets

    /// Snappy spring for small interactive elements (buttons, chips, icons).
    static let snap: Animation = .spring(duration: fast, bounce: 0.2)

    /// Smooth ease for standard UI transitions (reveals, expansions).
    static let smooth: Animation = .easeInOut(duration: normal)

    /// Gentle spring for larger view changes (sheets, cards, navigation).
    static let gentle: Animation = .spring(duration: slow, bounce: 0.15)
}
