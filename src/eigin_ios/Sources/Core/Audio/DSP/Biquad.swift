import Foundation

/// Single-channel biquad filter. Reference type: state persists across the
/// streaming chunks fed through the speech DSP chain.
final class Biquad {
    private var b0: Float = 1
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    // Direct form I state
    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    /// High-shelf coefficients per the RBJ cookbook (Q = 1/sqrt(2)).
    init(highShelfCornerHz corner: Float, gainDecibels: Float, sampleRate: Double) {
        let a = pow(10, Double(gainDecibels) / 40)
        let w0 = 2 * Double.pi * Double(corner) / sampleRate
        let cosW0 = Foundation.cos(w0)
        let sinW0 = Foundation.sin(w0)
        let sqrtA = a.squareRoot()
        let q = 1 / 2.squareRoot()
        let alpha = sinW0 / (2 * q)

        b0 = Float(a * ((a + 1) + (a - 1) * cosW0 + 2 * sqrtA * alpha))
        b1 = Float(-2 * a * ((a - 1) + (a + 1) * cosW0))
        b2 = Float(a * ((a + 1) + (a - 1) * cosW0 - 2 * sqrtA * alpha))
        let a0 = Float((a + 1) - (a - 1) * cosW0 + 2 * sqrtA * alpha)
        a1 = Float(2 * ((a - 1) - (a + 1) * cosW0))
        a2 = Float((a + 1) - (a - 1) * cosW0 - 2 * sqrtA * alpha)

        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0
    }

    /// Passes a chunk through the filter in place.
    func process(_ samples: inout [Float]) {
        var x1 = x1
        var x2 = x2
        var y1 = y1
        var y2 = y2
        for i in samples.indices {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
            samples[i] = y0
        }
        self.x1 = x1
        self.x2 = x2
        self.y1 = y1
        self.y2 = y2
    }
}
