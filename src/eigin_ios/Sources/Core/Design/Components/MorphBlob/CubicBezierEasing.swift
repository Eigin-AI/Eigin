import Foundation

/// Solver for CSS-style `cubic-bezier(x1, y1, x2, y2)` timing functions.
///
/// Only `y` is ever sampled, so the inner solver runs on the x axis only and
/// maps the found parameter to y.
struct CubicBezierEasing {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    /// Evaluates the eased progress at `t` in `[0, 1]`.
    func callAsFunction(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        return axisPolynomial(p1: y1, p2: y2)(solveX(t))
    }

    private var x: (Double) -> Double {
        axisPolynomial(p1: x1, p2: x2)
    }

    private var dx: (Double) -> Double {
        axisPolynomialDerivative(p1: x1, p2: x2)
    }

    /// Newton-Raphson with a bisection fallback, matching the precision
    /// browser timing functions provide.
    private func solveX(_ t: Double) -> Double {
        var parameter = t
        for _ in 0 ..< 8 {
            let error = x(parameter) - t
            if abs(error) < 1e-6 { break }
            let slope = dx(parameter)
            if abs(slope) < 1e-6 { break }
            parameter -= error / slope
            if parameter < 0 { parameter = 0 }
            if parameter > 1 { parameter = 1 }
        }
        // Bisection fallback if Newton stalled above tolerance.
        if abs(x(parameter) - t) > 1e-5 {
            var low = 0.0, high = 1.0
            parameter = t
            for _ in 0 ..< 24 {
                let at = x(parameter)
                if abs(at - t) < 1e-6 { break }
                if at < t { low = parameter } else { high = parameter }
                parameter = (low + high) / 2
            }
        }
        return parameter
    }
}

private func axisPolynomial(p1: Double, p2: Double) -> (Double) -> Double {
    { t in
        let m = 1 - t
        return 3 * m * m * t * p1 + 3 * m * t * t * p2 + t * t * t
    }
}

private func axisPolynomialDerivative(p1: Double, p2: Double) -> (Double) -> Double {
    { t in
        let m = 1 - t
        return 3 * m * m * p1 + 6 * m * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }
}
