import { forms, maxFormSize, POINT_COUNT, type Point } from "./forms";
import type { Pose } from "./timeline";

/**
 * What the blob draws at a moment: normalized sample points and the extents
 * they scale into. The seeded choreography is pulled toward the resting circle
 * by `intensity`, so 0 renders a plain still circle and 1 the full wobble.
 */
export interface MorphFigure {
  points: Point[];
  width: number;
  height: number;
}

/** Blends the pose between its two forms, then toward the resting circle. */
export function figureOf(pose: Pose, intensity: number): MorphFigure {
  const amount = Math.min(Math.max(intensity, 0), 1);
  const circle = forms[0];
  const from = forms[pose.from];
  const to = forms[pose.to];
  const progress = pose.progress;

  const width = lerp(from.width, to.width, progress);
  const height = lerp(from.height, to.height, progress);

  const points: Point[] = [];
  for (let i = 0; i < POINT_COUNT; i++) {
    const a = from.points[i];
    const b = to.points[i];
    const c = circle.points[i];
    points.push({
      x: c.x + (a.x + (b.x - a.x) * progress - c.x) * amount,
      y: c.y + (a.y + (b.y - a.y) * progress - c.y) * amount,
    });
  }
  return {
    points,
    width: circle.width + (width - circle.width) * amount,
    height: circle.height + (height - circle.height) * amount,
  };
}

/** Closed Catmull-Rom spline: a smooth outline through evenly spaced samples. */
export function splinePath(points: Point[]): string {
  const count = points.length;
  if (count < 3) return "";
  let d = `M ${points[0].x.toFixed(3)} ${points[0].y.toFixed(3)}`;
  for (let i = 0; i < count; i++) {
    const p0 = points[(i - 1 + count) % count];
    const p1 = points[i];
    const p2 = points[(i + 1) % count];
    const p3 = points[(i + 2) % count];
    const c1x = p1.x + (p2.x - p0.x) / 6;
    const c1y = p1.y + (p2.y - p0.y) / 6;
    const c2x = p2.x - (p3.x - p1.x) / 6;
    const c2y = p2.y - (p3.y - p1.y) / 6;
    d += ` C ${c1x.toFixed(3)} ${c1y.toFixed(3)}, ${c2x.toFixed(3)} ${c2y.toFixed(3)}, ${p2.x.toFixed(3)} ${p2.y.toFixed(3)}`;
  }
  return `${d} Z`;
}

/**
 * One library form at rest, as an SVG path in a `view`-sized box. Forms are
 * scaled off the largest in the library, so relative sizes stay true.
 */
export function formPath(index: number, view = 100, fill = 0.875): string {
  const form = forms[index];
  const scale = (view * fill) / maxFormSize;
  const center = view / 2;
  return splinePath(
    form.points.map((p) => ({
      x: center + (p.x * form.width * scale) / 2,
      y: center + (p.y * form.height * scale) / 2,
    })),
  );
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}
