/**
 * Chases a target value at a capped speed.
 *
 * Progress arrives in jumps — a step finishes, a percentage lands — and moving
 * a bar straight to each reported value reads as stuttering. This advances at
 * most `maxSpeed` units per second, so the bar always travels.
 *
 * A port of `ChasingProgress.swift`. Time is injected and `tick` is public, so
 * the chase can be stepped by hand.
 */
export class ChasingProgress {
  /** Current display value, 0–1. Drive the progress bar from this. */
  value = 0;
  /** True only once the target reached 1 and the value caught up. */
  isFinished = false;

  private target = 0;
  private lastTimestamp = 0;

  constructor(private readonly maxSpeed = 0.7) {}

  /** True while the value still has ground to cover. */
  get isChasing(): boolean {
    return !this.isFinished && this.value < this.target;
  }

  /** Sets a new target to chase, clamped to 0–1. */
  setTarget(target: number): void {
    this.target = Math.min(Math.max(target, 0), 1);
  }

  reset(): void {
    this.value = 0;
    this.target = 0;
    this.isFinished = false;
    this.lastTimestamp = 0;
  }

  /** Advances the value toward the target. `timestamp` is in seconds. */
  tick(timestamp: number): void {
    // Assume a nominal 10fps for the first frame, having nothing to diff against.
    const dt = this.lastTimestamp > 0 ? Math.max(0, timestamp - this.lastTimestamp) : 1 / 10;
    this.lastTimestamp = timestamp;

    const remaining = this.target - this.value;
    this.value =
      remaining <= 0 ? this.target : this.value + Math.min(this.maxSpeed * dt, remaining);

    if (this.value >= 0.99 && this.target >= 1) this.isFinished = true;
  }
}
