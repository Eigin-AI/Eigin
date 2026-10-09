// The banner's blob: a short, seamless loop through the app's own MorphBlob forms.
import { CubicBezierEasing } from "../../../web/src/lib/components/morph/easing";
import { figureOf, splinePath } from "../../../web/src/lib/components/morph/figure";
import { maxFormSize } from "../../../web/src/lib/components/morph/forms";
import { BREATH_SCALE_AMPLITUDE } from "../../../web/src/lib/components/morph/timeline";

/** Forms visited in order; the last hands back to the first so the loop is seamless. */
const route = [4, 12, 6, 9];
/** Seconds per form: a glide, then a short settle. */
const TRAVEL = 1.6;
const HOLD = 0.9;
export const LOOP = route.length * (TRAVEL + HOLD);

const travelEasing = new CubicBezierEasing(0.37, 0, 0.63, 1);

/** The blob outline at `t` seconds, in a 0 to 100 viewBox. */
export function blobPath(t: number): string {
  const local = ((t % LOOP) + LOOP) % LOOP;
  const step = Math.floor(local / (TRAVEL + HOLD));
  const within = local - step * (TRAVEL + HOLD);
  const progress = within < HOLD ? 0 : travelEasing.at((within - HOLD) / TRAVEL);
  const figure = figureOf(
    { from: route[step], to: route[(step + 1) % route.length], progress },
    1,
  );

  // Two breaths per loop keeps the swell in phase at the seam.
  const breath = 1 + BREATH_SCALE_AMPLITUDE * 1.5 * Math.cos((local / LOOP) * 4 * Math.PI);
  const scale = (100 * 0.9) / maxFormSize;
  const halfWidth = (figure.width / 2) * scale * breath;
  const halfHeight = (figure.height / 2) * scale * breath;
  return splinePath(
    figure.points.map((p) => ({ x: 50 + p.x * halfWidth, y: 50 + p.y * halfHeight })),
  );
}
