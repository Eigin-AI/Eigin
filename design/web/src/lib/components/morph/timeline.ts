import { CubicBezierEasing } from "./easing";
import { forms } from "./forms";

/**
 * Deterministic timeline for the morphing blob.
 *
 * Everything the blob does is a pure function of elapsed time plus a seed: the
 * library position (pose), the scale-in on first appearance, and the slow
 * breath. No animation state is stored, so the blob can be torn down and
 * rebuilt and lands on exactly the same frame it left.
 */

/** Which two forms a moment sits between, and how far between them. */
export interface Pose {
  from: number;
  to: number;
  progress: number;
}

export const INITIAL_HOLD = 0.6;
export const ENTRY_DURATION = 0.4;
export const BREATH_PERIOD = 4.6;
export const BREATH_SCALE_AMPLITUDE = 0.022;

/** Travel/hold recipes; mixed weights give bursts punctuated by settles. */
const rhythms = [
  { travel: [0.42, 0.55], weight: 0.35 },
  { travel: [1.1, 1.35], weight: 0.4 },
  { travel: [1.25, 1.6], weight: 0.25 },
] as const;

/** A slight ease — the morph glides without a spring's bounce. */
const travelEasing = new CubicBezierEasing(0.37, 0, 0.63, 1);
/** Prototype entry easing: overshoots, settles. */
const entryEasing = new CubicBezierEasing(0.32, 1.4, 0.5, 1);

export class MorphTimeline {
  /** Library positions travelled through: starts and ends on the circle. */
  private readonly sequence: number[];
  /** Travel duration per segment. */
  private readonly segments: number[];
  /** How far the breath swells, and how long one cycle takes. */
  private readonly breathScaleAmplitude: number;
  private readonly breathPeriod: number;

  constructor(
    seed = 0x5eeda11c,
    options: { breathScaleAmplitude?: number; breathPeriod?: number } = {},
  ) {
    this.breathScaleAmplitude = options.breathScaleAmplitude ?? BREATH_SCALE_AMPLITUDE;
    this.breathPeriod = options.breathPeriod ?? BREATH_PERIOD;
    /* xorshift on a 64-bit state. Kept in
       BigInt because the shifts overflow a double. */
    let state = (BigInt(Math.floor(seed)) + 0x9e3779b97f4a7c15n) & 0xffffffffffffffffn;
    const next = (): bigint => {
      state = (state ^ (state << 13n)) & 0xffffffffffffffffn;
      state ^= state >> 7n;
      state = (state ^ (state << 17n)) & 0xffffffffffffffffn;
      return state;
    };
    const randomUnit = (): number => Number(next() >> 11n) / 2 ** 53;

    // Shuffle every form but the resting circle, then return to it so the
    // cycle loops seamlessly.
    const order = forms.map((_, i) => i).slice(1);
    for (let i = order.length - 1; i > 0; i--) {
      const j = Number(next() % BigInt(i + 1));
      [order[i], order[j]] = [order[j], order[i]];
    }
    this.sequence = [0, ...order, 0];

    this.segments = [];
    for (let i = 0; i < this.sequence.length - 1; i++) {
      const [low, high] = pickRhythm(randomUnit()).travel;
      this.segments.push(low + randomUnit() * (high - low));
    }
  }

  /** The forms travelled through, in order: starts and ends on the circle. */
  get formOrder(): readonly number[] {
    return this.sequence;
  }

  /** Seconds one full cycle takes, after the initial hold. */
  get cycleDuration(): number {
    return this.segments.reduce((sum, travel) => sum + travel, 0);
  }

  /** The blob's library position at `t` seconds after it appeared. */
  pose(t: number): Pose {
    if (t < INITIAL_HOLD || this.segments.length === 0) {
      return { from: 0, to: 0, progress: 0 };
    }
    // Long waits loop the choreography rather than freezing; the wrap lands
    // on the circle the blob entered with.
    let remaining = t - INITIAL_HOLD;
    const total = this.segments.reduce((sum, travel) => sum + travel, 0);
    if (total > 0) remaining %= total;

    for (let i = 0; i < this.segments.length; i++) {
      const travel = this.segments[i];
      if (remaining < travel) {
        return {
          from: this.sequence[i],
          to: this.sequence[i + 1],
          progress: travelEasing.at(remaining / travel),
        };
      }
      remaining -= travel;
    }
    return { from: 0, to: 0, progress: 0 };
  }

  /** Scale-in for the blob's first seconds; overshoots slightly on the way to 1. */
  entryScale(t: number): number {
    if (t <= 0) return 0;
    if (t >= ENTRY_DURATION) return 1;
    return entryEasing.at(t / ENTRY_DURATION);
  }

  /** The breath: a bare swell, scale only, never a drift. */
  breath(t: number): number {
    return (
      1 + this.breathScaleAmplitude * Math.sin((t / this.breathPeriod) * 2 * Math.PI + Math.PI / 2)
    );
  }
}

function pickRhythm(roll: number): (typeof rhythms)[number] {
  let cumulative = 0;
  for (const rhythm of rhythms) {
    cumulative += rhythm.weight;
    if (roll < cumulative) return rhythm;
  }
  return rhythms[rhythms.length - 1];
}
