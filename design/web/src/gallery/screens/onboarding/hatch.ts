import { figureOf, splinePath } from "@lib/components/morph/figure";
import { forms } from "@lib/components/morph/forms";
import { INITIAL_HOLD, MorphTimeline } from "@lib/components/morph/timeline";
import { springCurve } from "@lib/internal/spring";

/**
 * The agent's hatch, as pure functions of time in seconds. The green circle
 * with the mark breathes like it is working: it swells and gets agitated,
 * then contracts, and each contraction squeezes the mark. Three breaths, each
 * bigger, and the last squeezes the mark away; then it settles to a circle
 * with the agent's face in it. Everything reads one clock, so the moment can
 * be slowed or scrubbed.
 */

/** A beat of empty screen, then the circle with the mark grows in. */
const APPEARS = 0.45;
/** It has grown in and held a moment: the build-up begins. */
export const ARRIVED = APPEARS + 1.0;
/** The mark is gone: the blob settles to a circle and the face springs in. */
export const RELEASE = ARRIVED + 4.0;
/** Everything has come to rest, the last ripple included. */
export const SETTLED = RELEASE + 1.8;
/** The ripples have faded out completely: only now does the hatch move up. */
export const LANDS = RELEASE + 1.7;

/**
 * The blob's size through the build-up: firm, then three breaths out and in,
 * each bigger. A contraction is quick, a swell takes its time.
 */
const BREATHS = [
  { at: ARRIVED, size: 1 },
  { at: ARRIVED + 1.15, size: 1.14 },
  { at: ARRIVED + 1.5, size: 0.9 },
  { at: ARRIVED + 2.4, size: 1.2 },
  { at: ARRIVED + 2.75, size: 0.86 },
  { at: ARRIVED + 3.65, size: 1.24 },
  { at: RELEASE, size: 0.8 },
];
/** The last contraction: the one that takes the mark away. */
const LAST_SWELL = BREATHS[BREATHS.length - 2].at;

const grow = springCurve(0.6, 0.25);
const settle = springCurve(0.6, 0.45);
const pop = springCurve(0.5, 0.45);
/* The release: quick and bouncy, so it lands with a snap. */
const snap = springCurve(0.35, 0.45);

/** A max with a rounded corner `k` wide, so a floor never leaves a flat. */
const softMax = (a: number, b: number, k: number) => (a + b + Math.sqrt((a - b) ** 2 + k * k)) / 2;
const clamp = (value: number) => Math.min(Math.max(value, 0), 1);
const easeIn = (value: number) => value ** 3;
const easeOut = (value: number) => 1 - (1 - value) ** 3;
const smooth = (from: number, to: number, t: number) => {
  const x = clamp((t - from) / (to - from));
  return x * x * (3 - 2 * x);
};

/** Whether the mark is gone and the face is coming in. */
export function released(t: number): boolean {
  return t >= RELEASE;
}

/** The whole hatch growing in from nothing, after the empty beat. */
export function arrival(t: number): { opacity: number; scale: number } {
  return {
    opacity: clamp((t - APPEARS) / 0.1),
    scale: t < ARRIVED ? Math.max(grow(t - APPEARS), 0) : 1,
  };
}

/** The blob's size: the breaths, then a snap back out to the circle. */
function size(t: number): number {
  if (t >= RELEASE) return 0.8 + 0.2 * snap(t - RELEASE);
  for (let i = 1; i < BREATHS.length; i++) {
    const from = BREATHS[i - 1];
    const to = BREATHS[i];
    if (t < to.at) return from.size + (to.size - from.size) * smooth(from.at, to.at, t);
  }
  return 1;
}

/**
 * How agitated the blob is, 0–1. It steps up with each swell and firms up
 * as it contracts, so the moves are biggest when it is most open.
 */
function agitation(t: number): number {
  const level =
    0.35 * smooth(BREATHS[0].at, BREATHS[1].at, t) +
    0.3 * smooth(BREATHS[2].at, BREATHS[3].at, t) +
    0.35 * smooth(BREATHS[4].at, BREATHS[5].at, t);
  const open = clamp((size(t) - 0.86) / (1.2 - 0.86));
  return level * (0.35 + 0.65 * open);
}

/**
 * The face springs into the circle, untwisting as it lands. Sized rather than
 * transformed by the caller, so the glyph stays sharp at every frame.
 */
export function face(t: number): { scale: number; rotate: number; opacity: number } {
  const settled = pop(t - RELEASE - 0.06);
  return {
    scale: Math.max(settled, 0),
    rotate: -14 * (1 - settled),
    opacity: t < RELEASE ? 0 : 1,
  };
}

/* The thinking indicator's own choreography, so the blob reads as that one. */
const morph = new MorphTimeline(0x5eeda11c);
const circle = forms[0];

/** How far into the last breath, 0–1, eased in: the pace picks up toward the end. */
function finale(t: number): number {
  return smooth(BREATHS[4].at, RELEASE, t) ** 2;
}

/**
 * How worked up the blob is. `gain` exaggerates the thinking indicator's own
 * forms (1 is as-is); `stretch` pulls it long one way; `inset` presses a
 * couple of dents into it. All big and slow: a few large moves, never many
 * small bulges.
 */
function effort(t: number): { gain: number; stretch: number; inset: number } {
  const at = Math.min(t, RELEASE);
  const working = agitation(at);
  const fluid = smooth(ARRIVED, ARRIVED + 0.6, at);
  const moves = {
    gain: fluid * (0.6 + 2 * working) + 0.8 * finale(at),
    stretch: 0.03 * fluid + 0.17 * working + 0.05 * finale(at),
    inset: 0.1 * working,
  };
  if (!released(t)) return moves;
  // Settles back to the circle on a spring, wobbling once past round.
  const left = 1 - settle(t - RELEASE);
  return { gain: moves.gain * left, stretch: moves.stretch * left, inset: moves.inset * left };
}

type Point = { x: number; y: number };

/**
 * The blob's outline at a unit radius, before the mark's floor: the thinking
 * indicator's forms exaggerated, a long stretch swinging round and a couple
 * of dents pressed in, sized by the breath alone.
 */
function shape(t: number, clock: number): Point[] {
  const { gain, stretch, inset } = effort(t);
  const figure = figureOf(morph.pose(clock), 1);
  const halfWidth = circle.width / 2 + (figure.width / 2 - circle.width / 2) * gain;
  const halfHeight = circle.height / 2 + (figure.height / 2 - circle.height / 2) * gain;
  // Turns with the morph's clock, so the swing quickens as the blob works.
  const swing = clock * 0.8;
  const press = 1 - clock * 0.45;

  const shaped = figure.points.map((p, i) => {
    const c = circle.points[i];
    const theta = (i / figure.points.length) * 2 * Math.PI;
    const bend = 1 + stretch * Math.cos(2 * (theta - swing)) + inset * Math.cos(3 * theta + press);
    return {
      x: (c.x + (p.x - c.x) * gain) * halfWidth * bend,
      y: (c.y + (p.y - c.y) * gain) * halfHeight * bend,
    };
  });

  // Exaggerating the morph exaggerates its forms' sizes too; only the shape
  // should be, so the size is the breath's alone.
  const mean = shaped.reduce((sum, p) => sum + Math.hypot(p.x, p.y), 0) / shaped.length;
  const fit = size(t) / mean;
  return shaped.map((p) => ({ x: p.x * fit, y: p.y * fit }));
}

/** Where an outline's mass sits: the centroid of the area it encloses. */
function centroid(points: Point[]): Point {
  let area = 0;
  let x = 0;
  let y = 0;
  for (let i = 0; i < points.length; i++) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    const cross = a.x * b.y - b.x * a.y;
    area += cross;
    x += (a.x + b.x) * cross;
    y += (a.y + b.y) * cross;
  }
  return area === 0 ? { x: 0, y: 0 } : { x: x / (3 * area), y: y / (3 * area) };
}

/** One damped spring step toward `target`, at `hz` with `damping` (1 is critical). */
function follow(
  state: { value: number; velocity: number },
  target: number,
  hz: number,
  damping: number,
): void {
  const omega = 2 * Math.PI * hz;
  const force = omega * omega * (target - state.value) - 2 * damping * omega * state.velocity;
  state.velocity += force * STEP;
  state.value += state.velocity * STEP;
}

const STEP = 1 / 120;
/** How far the mark may be carried off centre, in units of the blob's radius. */
const DRIFT = 0.11;

interface Frame {
  /** The morph's clock: faster the more agitated, about 6× by the release. */
  clock: number;
  /** The mark, in units of the blob's radius and degrees. */
  mark: { x: number; y: number; scale: number; rotate: number };
}

/**
 * The hatch simulated once, at 120 steps a second. The mark is a thing in the
 * dough: carried with the blob's mass, leaning where it goes, and squeezed as
 * it contracts, each on a spring, so it lags the blob and gives a little as
 * it recovers. Pure in time all the same: every frame is a lookup.
 */
const frames: Frame[] = (() => {
  const out: Frame[] = [];
  let clock = INITIAL_HOLD;
  const x = { value: 0, velocity: 0 };
  const y = { value: 0, velocity: 0 };
  const scale = { value: 1, velocity: 0 };
  const lean = { value: 0, velocity: 0 };
  for (let t = 0; t <= SETTLED + STEP; t += STEP) {
    if (t > ARRIVED) {
      const now = Math.min(t, RELEASE);
      clock += STEP * (1 + 2 * agitation(now) + 3 * finale(now));
    }
    const mass = centroid(shape(t, clock));
    // Carried with the mass, but never far off centre.
    const reach = Math.min(1, DRIFT / Math.max(Math.hypot(mass.x, mass.y), 1e-6));
    follow(x, mass.x * reach, 4, 0.55);
    follow(y, mass.y * reach, 4, 0.55);
    // A press, not a shrink: the mark gives about half as much as the blob.
    follow(scale, 1 - 0.55 * (1 - Math.min(1, size(t))), 4.5, 0.4);
    follow(lean, 40 * mass.x, 3, 0.5);
    out.push({
      clock,
      mark: { x: x.value, y: y.value, scale: scale.value, rotate: lean.value },
    });
  }
  return out;
})();

function frameAt(t: number): Frame {
  return frames[Math.min(Math.max(Math.round(t / STEP), 0), frames.length - 1)];
}

/**
 * The mark: carried and squeezed by the blob, as simulated above. The last
 * contraction takes it away to nothing, ending on the release.
 */
export function mark(t: number): { x: number; y: number; scale: number; rotate: number } {
  const { x, y, scale, rotate } = frameAt(t).mark;
  return { x, y, rotate, scale: scale * (1 - easeIn(smooth(LAST_SWELL, RELEASE, t))) };
}

/**
 * The blob, as a path in a box centred on 0. It starts as the exact circle,
 * then breathes and works like the thinking indicator, only harder. On the
 * release it snaps back to the circle. `swell` reaches the edge out at an
 * angle, in units of the radius.
 */
export function blob(
  t: number,
  radius: number,
  swell: (angle: number) => number = () => 0,
): string {
  const points = shape(t, frameAt(t).clock).map((p) => {
    const reached = radius * (1 + swell(Math.atan2(p.y, p.x)));
    return { x: p.x * reached, y: p.y * reached };
  });
  if (released(t)) return splinePath(points);

  // Never dents in far enough to bare the mark, wherever it is and however
  // small it is now.
  const held = mark(t);
  const centre = { x: held.x * radius, y: held.y * radius };
  const floor = radius * 0.86 * held.scale;
  return splinePath(
    points.map((p) => {
      const dx = p.x - centre.x;
      const dy = p.y - centre.y;
      const r = Math.hypot(dx, dy);
      const kept = softMax(r, floor, radius * 0.08) / r;
      return { x: centre.x + dx * kept, y: centre.y + dy * kept };
    }),
  );
}

/**
 * The radiating ripples: wobbly surfaces spreading from the release, like a
 * drop landing in water. Filled rather than outlined, each a little fainter
 * than the one inside it, and each pulsing as it spreads.
 */
export function ripples(t: number, radius: number): { path: string; opacity: number }[] {
  /* The outer a surface, the fainter: layered depth rather than a line. */
  const depths = [0.5, 0.3, 0.16];
  return [0, 1, 2].flatMap((index) => {
    const start = RELEASE + index * 0.11;
    const into = (t - start) / (0.9 + index * 0.12);
    if (into <= 0 || into >= 1) return [];
    const spread = easeOut(into);
    const size = radius * (1.05 + (1.6 - index * 0.3) * spread);
    const lobes = [{ k: 3, amount: 0.035 * (1 - into), phase: index * 2 + t * 2 }];
    /* Each surface breathes on its own clock, a beat out of step. */
    const pulse = 0.7 + 0.3 * Math.sin(t * 9 + index * 2.1);
    return [{ path: outline(size, lobes), opacity: depths[index] * pulse * (1 - into) }];
  });
}

/** A circle of `radius` deformed by cosine lobes, as a smooth closed path. */
function outline(radius: number, lobes: { k: number; amount: number; phase: number }[]): string {
  const count = 60;
  return splinePath(
    Array.from({ length: count }, (_, i) => {
      const theta = (i / count) * 2 * Math.PI;
      const r =
        radius *
        (1 + lobes.reduce((sum, l) => sum + l.amount * Math.cos(l.k * theta + l.phase), 0));
      return { x: r * Math.cos(theta), y: r * Math.sin(theta) };
    }),
  );
}
