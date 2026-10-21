import SwiftUI

/// One soft edge: content scrolling toward a screen edge fades into the
/// surface and blurs before it reaches the controls there.
///
/// Two overlays: a backdrop blur under the fade, the surface colour rising to
/// the edge. The blur is full from the screen edge part way down the
/// control, then eases out just past it, per ``SoftEdgeShape``. Both show
/// only while content is scrolled past the edge.
///
/// Anchored to the screen edge.
struct SoftEdge: View {
    let edge: VerticalEdge
    /// The safe area between the screen edge and the control.
    let inset: CGFloat
    /// The header or footer's height. 0 for none.
    let controlHeight: CGFloat
    let isActive: Bool

    @Environment(\.colors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.softEdgeShape) private var shape
    @State private var hasAppeared = false

    var body: some View {
        SoftEdgeLayers(
            edge: edge,
            blurFull: blurFull / height,
            blurEnd: blurEnd / height,
            tintLift: SoftEdgeCurve.tintLift(dark: colorScheme == .dark),
            surface: colors.surface.standard.base,
            visibility: isShown ? 1 : 0
        )
        // One animation drives every layer, so the blur and the colour over
        // it never drift apart mid-fade.
        .animation(Animations.smooth, value: isActive)
        .animation(entry, value: hasAppeared)
        .onAppear {
            // The entry waits for the system to turn the blur on once a push
            // settles, then fades in its own update: one shared with the push
            // could have animations turned off, and the blur would pop in.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(SoftEdgeCurve.blurEntryDelay))
                hasAppeared = true
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        // Never animate the soft edge's geometry, even inside an animated
        // update such as a tab switch.
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isShown: Bool {
        hasAppeared && isActive
    }

    private var entry: Animation {
        .easeOut(duration: SoftEdgeCurve.blurEntryDuration)
    }

    private var control: CGFloat {
        inset + controlHeight
    }

    private var height: CGFloat {
        controlHeight > 0 ? control + shape.fadeReach : shape.fadeReach
    }

    private var blurFull: CGFloat {
        controlHeight > 0 ? inset + controlHeight * shape.fullDepth : 0
    }

    private var blurEnd: CGFloat {
        controlHeight > 0 ? control + shape.overhang : height
    }
}

/// The soft edge's layers at a given visibility, from 0 to 1. Animatable, so
/// each frame of a fade sets the blur and the colours over it together.
private struct SoftEdgeLayers: View, Animatable {
    let edge: VerticalEdge
    let blurFull: Double
    let blurEnd: Double
    let tintLift: Double
    let surface: Color
    var visibility: Double

    nonisolated var animatableData: Double {
        get { visibility }
        set { visibility = newValue }
    }

    var body: some View {
        ZStack {
            SoftEdgeBlur(edge: edge, full: blurFull, end: blurEnd, visibility: visibility)
            tintBalance
            fade
        }
        // Each frame sets the layers outright: only visibility animates,
        // never their size or position.
        .transaction { $0.animation = nil }
    }

    private var towardEdge: UnitPoint {
        edge == .top ? .top : .bottom
    }

    private var towardContent: UnitPoint {
        edge == .top ? .bottom : .top
    }

    /// Takes back the brightness the blur's tint adds, in step with its mask.
    /// Subtracting, unlike painting the surface over it, cancels the tint
    /// evenly through the transition and keeps the blurred content's contrast.
    private var tintBalance: some View {
        let lift = tintLift * visibility
        return LinearGradient(
            stops: SoftEdgeCurve.blurStops(full: blurFull, end: blurEnd).map {
                Gradient.Stop(color: Color(white: 1 - $0.coverage * lift), location: $0.location)
            },
            startPoint: towardEdge,
            endPoint: towardContent
        )
        .blendMode(.plusDarker)
    }

    private var fade: some View {
        LinearGradient(
            stops: SoftEdgeCurve.fadeStops.map {
                Gradient.Stop(
                    color: surface.opacity($0.coverage * visibility),
                    location: $0.location
                )
            },
            startPoint: towardEdge,
            endPoint: towardContent
        )
    }
}

extension EnvironmentValues {
    /// Where soft edges place their blur around a header or footer.
    @Entry var softEdgeShape: SoftEdgeShape = .screen
}
