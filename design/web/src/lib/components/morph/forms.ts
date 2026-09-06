/**
 * The blob's form library.
 *
 * Any closed outline becomes a form: it is flattened to a dense polyline and
 * resampled to a fixed number of equidistant points. That shared point count —
 * with matched winding and start point — is what lets any form glide into any
 * other without a cut.
 */

export interface Point {
  x: number;
  y: number;
}

export interface MorphForm {
  /** Points normalised to [-1, 1], clockwise, starting nearest the +x axis. */
  points: Point[];
  /** Native size the normalised geometry scales into. */
  width: number;
  height: number;
}

/** Sample points every form carries — the invariant behind morphing. */
export const POINT_COUNT = 60;

interface Harmonic {
  lobes: number;
  amount: number;
  /** Degrees. */
  phase: number;
}

/** A deformed circle: r(θ) = 1 + Σ amount·cos(lobes·θ + phase). */
function blob(harmonics: Harmonic[]): Point[] {
  const steps = 160;
  const points: Point[] = [];
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * 2 * Math.PI;
    let radius = 1;
    for (const harmonic of harmonics) {
      radius += harmonic.amount * Math.cos(harmonic.lobes * t + (harmonic.phase * Math.PI) / 180);
    }
    points.push({ x: Math.cos(t) * radius, y: Math.sin(t) * radius });
  }
  return points;
}

/** A unit circle sampled densely so resampling keeps it round. */
function ellipse(): Point[] {
  const count = 240;
  const points: Point[] = [];
  for (let i = 0; i <= count; i++) {
    const t = (i / count) * 2 * Math.PI;
    points.push({ x: Math.cos(t), y: Math.sin(t) });
  }
  return points;
}

/** Resamples a closed polyline to `POINT_COUNT` points, equidistant by arc length. */
function resample(dense: Point[]): Point[] {
  if (dense.length < 2) return dense;

  const lengths: number[] = [];
  let total = 0;
  for (let i = 0; i < dense.length; i++) {
    const a = dense[i];
    const b = dense[(i + 1) % dense.length];
    const length = Math.hypot(b.x - a.x, b.y - a.y);
    lengths.push(length);
    total += length;
  }

  const points: Point[] = [];
  let walked = 0;
  let j = 0;
  for (let i = 0; i < POINT_COUNT; i++) {
    const target = (i / POINT_COUNT) * total;
    while (walked + lengths[j] < target && j < dense.length - 1) {
      walked += lengths[j];
      j += 1;
    }
    const t = lengths[j] > 0 ? (target - walked) / lengths[j] : 0;
    const a = dense[j];
    const b = dense[(j + 1) % dense.length];
    points.push({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
  }
  return points;
}

/** Centres on the bounding box and stretches each axis into [-1, 1]. */
function normalize(points: Point[]): Point[] {
  const xs = points.map((p) => p.x);
  const ys = points.map((p) => p.y);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  if (maxX <= minX || maxY <= minY) return points;
  const centerX = (minX + maxX) / 2;
  const centerY = (minY + maxY) / 2;
  return points.map((p) => ({
    x: (p.x - centerX) / ((maxX - minX) / 2),
    y: (p.y - centerY) / ((maxY - minY) / 2),
  }));
}

/** Enforces one winding so all forms traverse in the same direction. */
function forceClockwise(points: Point[]): Point[] {
  let area = 0;
  for (let i = 0; i < points.length; i++) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    area += a.x * b.y - b.x * a.y;
  }
  return area < 0 ? [...points].reverse() : points;
}

/** Rotates the sample order to start nearest +x, so tweens never spin. */
function align(points: Point[]): Point[] {
  let best = 0;
  let bestDistance = Infinity;
  points.forEach((p, i) => {
    const d = Math.hypot(p.x - 1, p.y);
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  });
  return [...points.slice(best), ...points.slice(0, best)];
}

function form(dense: Point[], size: number): MorphForm {
  return { points: align(normalize(forceClockwise(resample(dense)))), width: size, height: size };
}

/**
 * A family of near-circles — different weightings and slight wobbles, like one
 * hand-drawn circle shifting its weight between imperfect tracings. The one
 * place to add, remove or reorder forms.
 */
export const forms: MorphForm[] = [
  // The resting circle.
  form(ellipse(), 32),
  // Slightly smaller — a caught breath.
  form(ellipse(), 27),
  // Pulled out to the right.
  form(blob([{ lobes: 1, amount: 0.13, phase: 0 }]), 34),
  // Weighted toward the upper left.
  form(blob([{ lobes: 1, amount: 0.12, phase: 200 }]), 34),
  // Uneven: a hand-drawn wobble, heavier low-left.
  form(
    blob([
      { lobes: 1, amount: 0.11, phase: 35 },
      { lobes: 2, amount: 0.06, phase: 110 },
    ]),
    33,
  ),
  // Bottom-weighted with a subtly dented side.
  form(
    blob([
      { lobes: 1, amount: 0.14, phase: 90 },
      { lobes: 3, amount: 0.05, phase: 0 },
    ]),
    34,
  ),
  // Tilted oval.
  form(blob([{ lobes: 2, amount: 0.13, phase: 30 }]), 33),
  // Pulling harder: leaning lower-right.
  form(blob([{ lobes: 1, amount: 0.17, phase: 310 }]), 35),
  // Pulling harder: a stretchier oval.
  form(blob([{ lobes: 2, amount: 0.14, phase: 70 }]), 35),
  // Another uneven wobble, heavier to the left.
  form(
    blob([
      { lobes: 1, amount: 0.13, phase: 150 },
      { lobes: 2, amount: 0.08, phase: 20 },
    ]),
    33,
  ),
  // Pulled toward the lower left.
  form(blob([{ lobes: 1, amount: 0.15, phase: 120 }]), 34),
  // Wide oval with a light wobble.
  form(
    blob([
      { lobes: 2, amount: 0.12, phase: 10 },
      { lobes: 1, amount: 0.05, phase: 200 },
    ]),
    35,
  ),
  // Strong pull to the upper right with a soft dent opposite.
  form(
    blob([
      { lobes: 1, amount: 0.16, phase: 30 },
      { lobes: 3, amount: 0.05, phase: 90 },
    ]),
    35,
  ),
  // Wobbly, heavier to the left with a high-frequency dent.
  form(
    blob([
      { lobes: 1, amount: 0.12, phase: 300 },
      { lobes: 3, amount: 0.07, phase: 150 },
    ]),
    33,
  ),
];

/** The largest native form size; drawing scales figures off it. */
export const maxFormSize = Math.max(...forms.map((f) => Math.max(f.width, f.height)));
