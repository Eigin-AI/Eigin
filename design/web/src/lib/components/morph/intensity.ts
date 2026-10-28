/**
 * How much of the morph choreography is showing: 0 sits still on the resting
 * circle, 1 runs the full wobble. A pure function of time since the state last
 * changed, ramping over the slow duration (400ms), so phase changes blend into
 * the wobble instead of snapping.
 */
const RAMP = 0.4;

export class MorphIntensity {
  /** The value showing when the state changed — where the ramp starts. */
  private readonly start: number;

  constructor(
    private readonly engaged: boolean,
    /** Seconds on the same clock the blob uses. */
    private readonly changedAt: number,
    start?: number,
    private readonly duration = RAMP,
  ) {
    this.start = start ?? (engaged ? 0 : 1);
  }

  /** Fully engaged for the whole of time — the chat indicator's mode. */
  static readonly full = new MorphIntensity(true, -Infinity, 1);
  /** Never engaged for the whole of time. */
  static readonly none = new MorphIntensity(false, -Infinity, 0);

  /** A new state anchored at `change`, with an optional easing duration in seconds. */
  transitionedTo(engaged: boolean, change: number, duration = this.duration): MorphIntensity {
    return new MorphIntensity(engaged, change, this.value(change), duration);
  }

  value(at: number): number {
    const target = this.engaged ? 1 : 0;
    const elapsed = at - this.changedAt;
    // Snap the settled ends: the curve is flat there, and clock arithmetic
    // can land a hair inside the ramp.
    if (elapsed >= this.duration - 1e-6) return target;
    if (elapsed <= 0) return this.start;
    const progress = Math.min(Math.max(elapsed / this.duration, 0), 1);
    const eased = progress * progress * (3 - 2 * progress);
    return this.start + (target - this.start) * eased;
  }
}
