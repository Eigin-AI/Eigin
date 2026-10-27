import { expect, test } from "@playwright/test";

for (const locale of ["en", "da"]) {
  test(`${locale} illustrations pause CSS and SVG motion until resumed`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.setViewportSize({ width: 1440, height: 1000 });
    for (const route of ["trust/", ""]) {
      await page.goto(`/${locale}/${route}`);
      const regions = page.locator(".animated-illustration");
      for (const region of await regions.all()) {
        await region.scrollIntoViewIfNeeded();
        await expect(region).toHaveAttribute("data-active", "true");
        await region
          .getByRole("button", {
            name: locale === "en" ? "Pause illustration" : "Sæt illustration på pause",
          })
          .click();
        await expect(region).toHaveAttribute("data-active", "false");
        const before = await region
          .locator("svg:has(animate)")
          .evaluateAll((nodes) => nodes.map((node) => (node as SVGSVGElement).getCurrentTime()));
        await page.waitForTimeout(250);
        expect(
          await region
            .locator("svg:has(animate)")
            .evaluateAll((nodes) => nodes.map((node) => (node as SVGSVGElement).getCurrentTime())),
        ).toEqual(before);
        expect(
          await region.evaluate((element) =>
            element
              .getAnimations({ subtree: true })
              .filter((animation) => animation instanceof CSSAnimation)
              .every((animation) => animation.playState === "paused"),
          ),
        ).toBe(true);
        await page.locator("h1").scrollIntoViewIfNeeded();
        await region.scrollIntoViewIfNeeded();
        await expect(region).toHaveAttribute("data-active", "false");
        await region
          .getByRole("button", {
            name: locale === "en" ? "Play illustration" : "Afspil illustration",
          })
          .click();
        await expect(region).toHaveAttribute("data-active", "true");
      }
    }
  });
}

test("illustrations remain still with reduced motion or without JavaScript", async ({
  browser,
}) => {
  for (const options of [{ reducedMotion: "reduce" as const }, { javaScriptEnabled: false }]) {
    const context = await browser.newContext(options);
    const page = await context.newPage();
    await page.goto("/en/trust/");
    await page.locator(".animated-illustration").first().scrollIntoViewIfNeeded();
    await expect(page.locator(".illustration-playback button")).toHaveCount(0);
    const time = () =>
      page
        .locator("svg:has(animate)")
        .evaluateAll((nodes) => nodes.map((node) => (node as SVGSVGElement).getCurrentTime()));
    if (options.javaScriptEnabled !== false) {
      for (const region of await page.locator(".animated-illustration").all()) {
        await expect(region).toHaveAttribute("data-active", "false");
      }
      const before = await time();
      await page.waitForTimeout(250);
      expect(await time()).toEqual(before);
    } else {
      expect(
        await page
          .locator("animate")
          .evaluateAll((nodes) =>
            nodes.every((node) => node.getAttribute("begin") === "indefinite"),
          ),
      ).toBe(true);
    }
    await context.close();
  }
});
