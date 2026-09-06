import { expect, test } from "@playwright/test";
import { forms, maxFormSize, POINT_COUNT } from "../src/lib/components/morph/forms";
import { figureOf } from "../src/lib/components/morph/figure";
import { MorphIntensity } from "../src/lib/components/morph/intensity";
import { MorphTimeline } from "../src/lib/components/morph/timeline";

/* Pure geometry — the invariants that let any form tween into any other. */

test.describe("morph forms", () => {
  test("share a point count, winding and start point", () => {
    expect(forms).toHaveLength(14);
    for (const form of forms) {
      expect(form.points).toHaveLength(POINT_COUNT);

      // Normalised into [-1, 1] on both axes.
      const xs = form.points.map((p) => p.x);
      const ys = form.points.map((p) => p.y);
      expect(Math.min(...xs)).toBeCloseTo(-1, 6);
      expect(Math.max(...xs)).toBeCloseTo(1, 6);
      expect(Math.min(...ys)).toBeCloseTo(-1, 6);
      expect(Math.max(...ys)).toBeCloseTo(1, 6);

      // Sampling starts nearest the +x axis, so tweens never spin.
      expect(form.points[0].x).toBeGreaterThan(0.9);
      expect(Math.abs(form.points[0].y)).toBeLessThan(0.2);

      // One winding direction for every form.
      let area = 0;
      for (let i = 0; i < form.points.length; i++) {
        const a = form.points[i];
        const b = form.points[(i + 1) % form.points.length];
        area += a.x * b.y - b.x * a.y;
      }
      expect(area).toBeGreaterThan(0);
    }
    expect(maxFormSize).toBe(35);
  });

  test("the resting form is a true circle", () => {
    const radii = forms[0].points.map((p) => Math.hypot(p.x, p.y));
    expect(Math.max(...radii) - Math.min(...radii)).toBeLessThan(1e-3);
  });
});

test.describe("morph timeline", () => {
  test("visits every form once and loops seamlessly", () => {
    const timeline = new MorphTimeline(1234);

    // Holds the circle, then travels.
    expect(timeline.pose(0.3)).toEqual({ from: 0, to: 0, progress: 0 });
    const travelling = [1, 2, 3, 5, 8].map((t) => timeline.pose(t));
    expect(travelling.some((pose) => pose.to !== 0 || pose.progress > 0)).toBe(true);
    for (const pose of travelling) {
      expect(pose.progress).toBeGreaterThanOrEqual(0);
      expect(pose.progress).toBeLessThanOrEqual(1);
    }

    // Every form is visited once, opening and closing on the circle.
    const order = timeline.formOrder;
    expect(order[0]).toBe(0);
    expect(order[order.length - 1]).toBe(0);
    expect(new Set(order).size).toBe(forms.length);

    // The choreography loops rather than freezing on long waits.
    const cycle = timeline.cycleDuration;
    expect(cycle).toBeGreaterThan(0);
    for (const offset of [0.1, 1.7, 4.2]) {
      const first = timeline.pose(0.6 + offset);
      const looped = timeline.pose(0.6 + offset + cycle);
      expect(looped.from).toBe(first.from);
      expect(looped.to).toBe(first.to);
      expect(looped.progress).toBeCloseTo(first.progress, 9);
    }
  });

  test("entry overshoots then settles", () => {
    const timeline = new MorphTimeline(1);
    expect(timeline.entryScale(0)).toBe(0);
    const peak = Math.max(
      ...Array.from({ length: 40 }, (_, i) => timeline.entryScale((i / 40) * 0.4)),
    );
    expect(peak).toBeGreaterThan(1);
    expect(timeline.entryScale(0.4)).toBe(1);
    expect(timeline.entryScale(10)).toBe(1);
  });

  test("breath is a barely visible swell", () => {
    const timeline = new MorphTimeline(1);
    const values = Array.from({ length: 200 }, (_, i) => timeline.breath((i / 200) * 4.6));
    expect(Math.max(...values)).toBeCloseTo(1.022, 6);
    expect(Math.min(...values)).toBeCloseTo(0.978, 6);
  });
});

test.describe("morph intensity", () => {
  test("ramps monotonically between the settled ends", () => {
    expect(MorphIntensity.full.value(0)).toBe(1);
    expect(MorphIntensity.none.value(0)).toBe(0);

    const ramp = new MorphIntensity(true, 0);
    expect(ramp.value(0)).toBe(0);
    expect(ramp.value(0.4)).toBe(1);
    const samples = Array.from({ length: 20 }, (_, i) => ramp.value((i / 20) * 0.4));
    for (let i = 1; i < samples.length; i++) {
      expect(samples[i]).toBeGreaterThanOrEqual(samples[i - 1]);
    }
  });

  test("a still blob is exactly the resting circle", () => {
    const figure = figureOf({ from: 5, to: 7, progress: 0.5 }, 0);
    expect(figure.width).toBe(32);
    figure.points.forEach((point, i) => {
      expect(point.x).toBeCloseTo(forms[0].points[i].x, 12);
      expect(point.y).toBeCloseTo(forms[0].points[i].y, 12);
    });
  });
});

test.describe("morph blob rendering", () => {
  /* The loop parks when the blob settles. Re-engaging must restart it — a
     parked loop leaves its clock stale, which once stranded the blob on a
     still circle for good. */
  test("wobbles, settles, and wobbles again", async ({ page }) => {
    await page.goto("/#/components/morph");
    const blob = page.locator(".slot path").first();
    await expect(blob).toBeVisible();

    const moves = async () => {
      const before = await blob.getAttribute("d");
      await page.waitForTimeout(500);
      return before !== (await blob.getAttribute("d"));
    };

    expect(await moves()).toBe(true);

    await page.getByRole("button", { name: "Settle to circle" }).click();
    await page.waitForTimeout(1200);
    expect(await moves()).toBe(false);

    await page.getByRole("button", { name: "Start wobbling" }).click();
    await page.waitForTimeout(600);
    expect(await moves()).toBe(true);
  });
});
