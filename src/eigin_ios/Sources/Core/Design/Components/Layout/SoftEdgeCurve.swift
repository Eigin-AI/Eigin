import Foundation

/// The shape of the soft edge: the fade and the blur's mask. One definition
/// serves every edge on every screen, so screens never tune it.
///
/// Locations run from 0 at the screen edge to 1 at the end of the soft edge.
enum SoftEdgeCurve {
    /// Surface coverage of the fade at the screen edge. Below full, as the
    /// blur does much of the hiding.
    static let fadeStrength = 0.5

    /// Fade coverage runs `fadeStrength · (1 - x)^fadeExponent`. Above 1, the
    /// content keeps more of itself through the middle.
    static let fadeExponent = 1.6

    /// Brightness the system blur's tint adds at full coverage, subtracted
    /// along its mask so the blur matches the screen. Raise a value if the
    /// blur still reads brighter, lower it if darker.
    static func tintLift(dark: Bool) -> Double {
        dark ? 0.06 : 0.03
    }

    /// The blur fades in after its screen appears, hiding the moment the
    /// system turns backdrop blur on once a push settles. In seconds.
    static let blurEntryDelay = 0.3
    static let blurEntryDuration = 0.35

    /// Gradient segments in each curve.
    static let steps = 32

    /// Fade coverage at `x`.
    static func fadeCoverage(at x: Double) -> Double {
        fadeStrength * pow(1 - x, fadeExponent)
    }

    /// Blur coverage at `t`, from 0 where it starts easing out to 1 where it
    /// ends: flat at both ends, so it leaves no edge.
    static func blurCoverage(at t: Double) -> Double {
        1 - t * t * (3 - 2 * t)
    }

    /// Fade stops across the soft edge.
    static var fadeStops: [(location: Double, coverage: Double)] {
        (0 ... steps).map { step in
            let x = Double(step) / Double(steps)
            return (location: x, coverage: fadeCoverage(at: x))
        }
    }

    /// Blur mask stops: full from the screen edge to `full`, easing out to
    /// none at `end`, both shares of the soft edge's height.
    static func blurStops(full: Double, end: Double) -> [(location: Double, coverage: Double)] {
        let ease = (0 ... steps).map { step in
            let t = Double(step) / Double(steps)
            return (location: full + t * (end - full), coverage: blurCoverage(at: t))
        }
        return [(location: 0, coverage: 1)] + ease + [(location: 1, coverage: 0)]
    }
}

/// Where a soft edge's blur sits around its header or footer. Screens keep it
/// tight to the control; sheets, whose header carries a description, reach
/// further so text beneath it doesn't stay legible.
struct SoftEdgeShape: Equatable {
    /// How far down the control the blur stays full, as a share of its height.
    var fullDepth: Double
    /// How far the blur reaches past the control, in points.
    var overhang: Double
    /// How far the fade reaches past the control, in points.
    var fadeReach: Double

    static let screen = SoftEdgeShape(fullDepth: 0.4, overhang: 16, fadeReach: 40)
    static let sheet = SoftEdgeShape(fullDepth: 1, overhang: 44, fadeReach: 52)
}
