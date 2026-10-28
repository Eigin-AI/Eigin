import { expect, test } from "@playwright/test";

test("the CTA blob holds its shape off-screen and resumes without jumping", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/en/");
  const region = page.locator(".get-stage");
  const path = region.locator(".morph-blob path");
  expect(
    await path.evaluate((element) => (element as SVGGraphicsElement).getBBox().width),
  ).toBeGreaterThan(35);
  await region.scrollIntoViewIfNeeded();
  await expect(region).toHaveAttribute("data-active", "true");
  await page.waitForTimeout(4000);

  for (const pause of ["off-screen", "button"]) {
    if (pause === "off-screen") {
      await page.locator("h1").scrollIntoViewIfNeeded();
    } else {
      await region.getByRole("button", { name: "Pause illustration" }).click();
    }
    await expect(region).toHaveAttribute("data-active", "false");
    const held = await path.getAttribute("d");
    await page.waitForTimeout(1500);
    expect(await path.getAttribute("d")).toBe(held);

    const resumed = region.evaluate(
      (element) =>
        new Promise<string>((resolve) => {
          const path = element.querySelector(".morph-blob path")!;
          const observer = new MutationObserver(() => {
            if (element.getAttribute("data-active") !== "true") return;
            observer.disconnect();
            resolve(path.getAttribute("d")!);
          });
          observer.observe(path, { attributes: true, attributeFilter: ["d"] });
        }),
    );
    if (pause === "off-screen") {
      await region.scrollIntoViewIfNeeded();
    } else {
      await region.getByRole("button", { name: "Play illustration" }).click();
    }
    const first = await resumed;
    const coordinates = (path: string) => path.match(/-?\d+(?:\.\d+)?/g)!.map(Number);
    const before = coordinates(held!);
    const after = coordinates(first);
    expect(after).toHaveLength(before.length);
    expect(Math.max(...after.map((value, i) => Math.abs(value - before[i])))).toBeLessThan(0.5);
    await page.waitForTimeout(500);
    expect(await path.getAttribute("d")).not.toBe(first);
  }
});
