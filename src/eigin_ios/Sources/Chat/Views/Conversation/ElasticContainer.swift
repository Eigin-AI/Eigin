import QuartzCore
import SwiftUI

/// A container that smoothly grows to fit its content height.
///
/// Uses a CADisplayLink to interpolate the displayed height toward
/// the content's measured height, closing a fraction of the gap
/// each frame. Larger gaps → faster growth.
struct ElasticContainer<Content: View>: View {
    var isActive: Bool
    @ViewBuilder let content: Content

    @State private var targetHeight: CGFloat = 0
    @State private var displayedHeight: CGFloat = 0
    @State private var fadeHeight: CGFloat = 0
    @State private var displayLink: CADisplayLink?

    /// Fraction of the gap consumed each tick.
    /// Higher than text throttling (0.09) because height jumps are more jarring.
    private let catchUpRate: CGFloat = 0.15

    /// Stop interpolating when closer than this many points.
    private let tolerance: CGFloat = 0.5

    /// Maximum fade gradient height (roughly 2-3 lines of body text).
    private let maxFadeHeight: CGFloat = 60

    /// Smoothing factor for fade height — slower than the height interpolation
    /// so the fade lingers briefly after a burst of content.
    private let fadeSmoothingRate: CGFloat = 0.08

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                targetHeight = newHeight
                if isActive {
                    startTimerIfNeeded()
                } else {
                    displayedHeight = newHeight
                    fadeHeight = 0
                }
            }
            .frame(height: isActive ? displayedHeight : targetHeight, alignment: .top)
            .mask {
                if isActive, fadeHeight > 1 {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeHeight)
                    }
                } else {
                    Color.black
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    // Starting streaming — seed displayed height so content isn't clipped to 0
                    if displayedHeight < tolerance {
                        displayedHeight = targetHeight
                    }
                } else {
                    stopTimer()
                    displayedHeight = targetHeight
                    fadeHeight = 0
                }
            }
            .onDisappear {
                stopTimer()
            }
    }

    // MARK: - Display Link

    private func startTimerIfNeeded() {
        guard displayLink == nil else { return }
        let trampoline = DisplayLinkTrampoline { [self] in
            tick()
        }
        let link = CADisplayLink(
            target: trampoline,
            selector: #selector(DisplayLinkTrampoline.tick)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        let gap = targetHeight - displayedHeight

        // Fade height tracks the gap — large gap means fast streaming, more fade.
        // Smoothed separately so it lingers briefly after a burst.
        let targetFade = min(gap, maxFadeHeight)
        let fadeDelta = targetFade - fadeHeight
        fadeHeight += fadeDelta * fadeSmoothingRate

        if abs(gap) < tolerance {
            displayedHeight = targetHeight
            fadeHeight = 0
            stopTimer()
            return
        }
        let advance = max(tolerance, gap * catchUpRate)
        displayedHeight = min(displayedHeight + advance, targetHeight)
    }
}

// MARK: - Lightweight grow-in for one-shot insertions

/// Animates content from zero height to its natural size on appear.
///
/// Unlike ``ElasticContainer`` this uses SwiftUI's animation system
/// instead of a CADisplayLink — no per-frame callbacks, zero ongoing cost.
/// Use for items that appear once at a known size (tool groups, status items).
struct GrowInContainer<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var measuredHeight: CGFloat = 0
    @State private var revealed = false

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                measuredHeight = $0
            }
            .frame(height: revealed ? measuredHeight : 0, alignment: .top)
            .clipped()
            .onAppear {
                withAnimation(.spring(duration: 0.35, bounce: 0)) {
                    revealed = true
                }
            }
    }
}

// MARK: - Grow-in modifier (identity-stable)

/// ViewModifier variant of ``GrowInContainer``.
///
/// Unlike the wrapper view, applying this as a `.modifier()` does **not**
/// change the view's structural identity when `isNew` flips to `false`.
/// `@State` survives the transition, so items that grew in during streaming
/// keep their full height when the streaming turn ends — no view recreation,
/// no layout pop.
private struct GrowInModifier: ViewModifier {
    let isNew: Bool

    @State private var measuredHeight: CGFloat = 0
    @State private var revealed = false

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                measuredHeight = $0
            }
            .frame(
                height: isNew && !revealed ? 0 : (isNew ? measuredHeight : nil),
                alignment: .top
            )
            .clipped()
            .onAppear {
                if isNew, !revealed {
                    withAnimation(.spring(duration: 0.35, bounce: 0)) {
                        revealed = true
                    }
                }
            }
    }
}

extension View {
    /// Animates this view growing from zero height when it first appears
    /// during a streaming turn. Identity-stable: no view recreation when
    /// `isNew` later becomes `false`.
    func growIn(isNew: Bool) -> some View {
        modifier(GrowInModifier(isNew: isNew))
    }
}

// MARK: - CADisplayLink trampoline

private final class DisplayLinkTrampoline: @unchecked Sendable {
    let action: @MainActor () -> Void
    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func tick() {
        MainActor.assumeIsolated { [action] in action() }
    }
}
