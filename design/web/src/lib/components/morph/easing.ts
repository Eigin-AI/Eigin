/** Solver for CSS-style `cubic-bezier(x1, y1, x2, y2)` timing functions. */
export class CubicBezierEasing {
  constructor(
    private readonly x1: number,
    private readonly y1: number,
    private readonly x2: number,
    private readonly y2: number,
  ) {}

  /** Eased progress at `t` in [0, 1]. */
  at(t: number): number {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return axis(this.y1, this.y2, this.solveX(t));
  }

  /** Newton-Raphson with a bisection fallback, as browsers do. */
  private solveX(t: number): number {
    let parameter = t;
    for (let i = 0; i < 8; i++) {
      const error = axis(this.x1, this.x2, parameter) - t;
      if (Math.abs(error) < 1e-6) break;
      const slope = axisDerivative(this.x1, this.x2, parameter);
      if (Math.abs(slope) < 1e-6) break;
      parameter = Math.min(1, Math.max(0, parameter - error / slope));
    }
    if (Math.abs(axis(this.x1, this.x2, parameter) - t) > 1e-5) {
      let low = 0;
      let high = 1;
      parameter = t;
      for (let i = 0; i < 24; i++) {
        const at = axis(this.x1, this.x2, parameter);
        if (Math.abs(at - t) < 1e-6) break;
        if (at < t) low = parameter;
        else high = parameter;
        parameter = (low + high) / 2;
      }
    }
    return parameter;
  }
}

function axis(p1: number, p2: number, t: number): number {
  const m = 1 - t;
  return 3 * m * m * t * p1 + 3 * m * t * t * p2 + t * t * t;
}

function axisDerivative(p1: number, p2: number, t: number): number {
  const m = 1 - t;
  return 3 * m * m * p1 + 6 * m * t * (p2 - p1) + 3 * t * t * (1 - p2);
}
