import { springCurve } from "@gallery/screens/onboarding/spring";

/**
 * The opening and the rhythm of the setup screens, in seconds unless named in
 * ms. Mirrors `OnboardingTiming` and `OpeningTimeline` on iOS; keep them in step.
 *
 * The opening picks the mark up where the launch screen left it, centred and
 * large: it holds as the plain circle, then works up the energy to jump, like
 * the start of the hatch: it swells, then crouches (squashed wide, pressed
 * down a touch). On the release it pushes itself up, stretched tall by its
 * speed, and lands in its place as a firm circle at its normal size.
 */

/** How long the mark holds at centre, picking up from the launch screen. */
export const HOLD = 0.4;
/** One breath, like the start of the hatch, snap-back included. */
export const BREATH = 1.75;
/* The breath, in seconds into it: a slow swell, a quick squeeze, then a
   snap back to round from the release. */
const SWELL = 0.9;
const RELEASE = SWELL + 0.3;
/** The rise from centre to the avatar's place, starting on the release. */
export const RISE = 0.8;
const RISES_AT = HOLD + RELEASE;
/** Done moving, the spring's tail included. */
export const OPENED = Math.max(HOLD + BREATH, RISES_AT + RISE * 2);

/** When the welcome title starts: as the rise settles, not after it. */
export const WELCOME_TITLE_DELAY_MS = (RISES_AT + RISE * 0.6) * 1000;
/** The outgoing screen's fade. The next title waits for it. */
export const TURN_FADE_MS = 200;
/** Beat before each later screen's title, so it starts once the old one is gone. */
export const TURN_TITLE_DELAY_MS = 250;
/** Beat between the title appearing and the body streaming. */
export const STREAM_DELAY_MS = 600;
/** Pace of the simulated stream, per word. */
export const WORD_INTERVAL_MS = 45;
/** Beat after the line lands before the screen's content appears. */
export const CONTENT_DELAY_MS = 700;

/** The launch screen's mark diameter in points, which the opening starts at.
   Matches `LaunchMark.diameter` on iOS and `MARK_DIAMETER_POINTS` in
   tools/src/design/ios/launch.rs; change all three together. */
const LAUNCH_DIAMETER = 128;

const rise = springCurve(RISE, 0.2);
const clamp = (x: number) => Math.min(Math.max(x, 0), 1);

/** The rise's speed at `t` seconds in, as a share of its fastest. */
function riseSpeed(t: number): number {
  const h = 1 / 240;
  return (rise(t + h) - rise(t - h)) / (2 * h) / PEAK_SPEED;
}
const PEAK_SPEED = Math.max(
  ...Array.from(
    { length: 200 },
    (_, i) => (rise(i / 100 + 1 / 240) - rise(i / 100 - 1 / 240)) * 120,
  ),
);

/** How deep the crouch is: in through the squeeze, out on the release, overshooting. */
function crouch(t: number): number {
  if (t < RISES_AT) return smooth(HOLD + SWELL, RISES_AT, t);
  return 1 - snap(t - RISES_AT);
}

/**
 * Where the avatar is `t` seconds into the opening: `rise` from centre (0) to
 * its slot (1), `scale` from the launch mark's size to 1, how far through its
 * breath the green circle is, and its `stretch`: tall above 0, wide below.
 * `launchScale` makes the vessel match the launch screen's mark.
 */
export function opening(
  t: number,
  launchScale: number,
): { rise: number; scale: number; breath: number; stretch: number } {
  const settled = rise(t - RISES_AT);
  const down = crouch(t);
  return {
    // Pressed down a touch in the crouch, the push-off for the jump.
    rise: settled - 0.02 * Math.max(down, 0),
    scale: launchScale + (1 - launchScale) * settled,
    breath: clamp((t - HOLD) / BREATH),
    // Squashed wide by the crouch, pulled tall by the speed of the rise.
    stretch: -0.09 * down + 0.14 * riseSpeed(t - RISES_AT),
  };
}

/** The scale at which a vessel `vesselSize` across matches the launch mark. */
export function launchScale(vesselSize: number): number {
  return LAUNCH_DIAMETER / vesselSize;
}

const SWOLLEN = 1.08;
const SQUEEZED = 0.93;
/* The hatch's release springs: a snap out, a bouncy settle of the shape. */
const snap = springCurve(0.35, 0.45);
const settle = springCurve(0.6, 0.45);

const smooth = (from: number, to: number, t: number) => {
  const x = clamp((t - from) / (to - from));
  return x * x * (3 - 2 * x);
};

/** The blob's size, as a share of its radius, `t` seconds into the breath. */
function breathSize(t: number): number {
  if (t < SWELL) return 1 + (SWOLLEN - 1) * smooth(0, SWELL, t);
  if (t < RELEASE) return SWOLLEN + (SQUEEZED - SWOLLEN) * smooth(SWELL, RELEASE, t);
  return SQUEEZED + (1 - SQUEEZED) * snap(t - RELEASE);
}

/**
 * The green circle `progress` (0–1) through its breath: one breath like the
 * start of the hatch. It swells as it stretches long and lumpy, squeezes in
 * quickly, pressing the mark, then snaps back out to the circle. `points` is
 * the outline on a unit circle centred on 0; `mark` scales the brand mark.
 */
export function outline(progress: number): { points: { x: number; y: number }[]; mark: number } {
  if (progress <= 0 || progress >= 1) {
    return { points: circlePoints(() => 1), mark: 1 };
  }
  const t = progress * BREATH;
  const size = breathSize(t);
  // Most worked up when most open; firms up as it squeezes, then lets go.
  const open = clamp((size - SQUEEZED) / (SWOLLEN - SQUEEZED));
  const build = smooth(0, SWELL * 0.6, t);
  const left = t < RELEASE ? 1 : 1 - settle(t - RELEASE);
  const stretch = (0.02 + 0.08 * open) * build * left;
  const inset = 0.045 * open * build * left;
  // The long axis swings round as it works.
  const swing = 0.4 + 1.1 * t;
  const press = 1 - 0.8 * t;
  return {
    points: circlePoints(
      (theta) =>
        size * (1 + stretch * Math.cos(2 * (theta - swing)) + inset * Math.cos(3 * theta + press)),
    ),
    // A press, not a shrink: the mark gives about half as much as the blob.
    mark: 1 - 0.55 * (1 - Math.min(1, size)),
  };
}

function circlePoints(radius: (theta: number) => number): { x: number; y: number }[] {
  return Array.from({ length: 60 }, (_, i) => {
    const theta = (i / 60) * 2 * Math.PI;
    const r = radius(theta);
    return { x: r * Math.cos(theta), y: r * Math.sin(theta) };
  });
}
