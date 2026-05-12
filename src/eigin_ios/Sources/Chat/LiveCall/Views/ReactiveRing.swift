import SwiftUI

/// Single unified ring that animates smoothly between call phases.
///
/// All phase appearances are expressed as computed properties on one view,
/// so SwiftUI can interpolate between them on phase transitions instead of
/// doing structural view swaps. Three continuous oscillations run in the
/// background (idle breathing, listening glow, processing rotation) — each
/// only affects the visual output when its phase is active.
struct ReactiveRing: View {
    let phase: LiveCallService.Phase

    @Environment(\.colors) private var colors

    // Continuous oscillations — always running, each at its own cadence.
    @State private var slowPulse = false // 2.5s cycle — idle breathing
    @State private var fastPulse = false // 1.5s cycle — listening glow
    @State private var speakingPulse = false // 1.8s cycle — speaking breath
    @State private var rotation: Double = 0 // continuous spin — processing comet

    private var accent: Color {
        colors.accent
    }

    // MARK: - Per-phase computed properties

    private var strokeColor: Color {
        switch phase {
        case .idle: colors.textTertiary
        case .listening: fastPulse ? accent : colors.textSecondary
        case .processing: accent
        case .speaking: accent
        }
    }

    private var strokeOpacity: Double {
        switch phase {
        case .idle: slowPulse ? 0.5 : 0.2
        case .listening: fastPulse ? 0.8 : 0.35
        case .processing: 0.8
        case .speaking: 0.8
        }
    }

    private var strokeWidth: CGFloat {
        switch phase {
        case .speaking: speakingPulse ? 7 : 3
        default: 2
        }
    }

    private var ringScale: CGFloat {
        switch phase {
        case .idle: slowPulse ? 1.03 : 1.0
        default: 1.0
        }
    }

    private var shadowColor: Color {
        switch phase {
        case .listening: fastPulse ? accent.opacity(0.3) : .clear
        default: .clear
        }
    }

    private var shadowRadius: CGFloat {
        phase == .listening ? 8 : 0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Base ring — always visible
            Circle()
                .stroke(colors.border, lineWidth: 2)

            // Gradient ring — fades in during processing
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            accent,
                            accent.opacity(0.6),
                            .clear,
                            .clear,
                            accent.opacity(0.3),
                            accent,
                        ]),
                        center: .center
                    ),
                    lineWidth: 2
                )
                .rotationEffect(.degrees(rotation))
                .opacity(phase == .processing ? 1 : 0)
                .animation(Animations.gentle, value: phase)

            // Solid ring — idle, listening, speaking
            Circle()
                .stroke(strokeColor.opacity(strokeOpacity), lineWidth: strokeWidth)
                .scaleEffect(ringScale)
                .shadow(color: shadowColor, radius: shadowRadius)
                .opacity(phase == .processing ? 0 : 1)
                .animation(Animations.gentle, value: phase)
        }
        .geometryGroup()
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                slowPulse = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                fastPulse = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                speakingPulse = true
            }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
