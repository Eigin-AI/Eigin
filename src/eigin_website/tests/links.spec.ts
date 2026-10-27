import { test, expect } from "@playwright/test";

test("arrow icons center on the link text lowercase height", async ({ page }) => {
  for (const locale of ["en", "da"]) {
    for (const suffix of ["", "roadmap/"]) {
      await page.goto(`/${locale}/${suffix}`);
      await page.evaluate(() => document.fonts.ready);
      for (const label of await page.locator(".arrow-link-label").all()) {
        const text = (await label.locator(".arrow-link-text").boundingBox())!;
        const icon = (await label.locator(".arrow-link-icon").boundingBox())!;
        const xHeight = await label.locator(".arrow-link-text").evaluate((element) => {
          const probe = document.createElement("span");
          probe.style.cssText = "position:absolute;height:1ex;width:0;pointer-events:none";
          element.append(probe);
          const height = probe.getBoundingClientRect().height;
          probe.remove();
          return height;
        });
        const textCenter = text.y + text.height - xHeight / 2;
        expect(Math.abs(textCenter - icon.y - icon.height / 2)).toBeLessThan(0.5);
      }
    }
  }
});

for (const path of ["/en/", "/en/roadmap/"]) {
  test(`${path} arrow links respond to hover and keyboard focus`, async ({ page, browserName }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.goto(path);
    const link = page.locator(".arrow-link").first();
    const icon = link.locator(".arrow-link-icon");
    await expect(icon.locator("svg")).toHaveCount(1);
    await page.evaluate(() => document.fonts.ready);
    await link.evaluate((element) =>
      Promise.allSettled(element.getAnimations().map((animation) => animation.finished)),
    );
    const originalColor = await link.evaluate((element) => getComputedStyle(element).color);
    await link.hover();
    await expect
      .poll(() => link.evaluate((element) => getComputedStyle(element).color))
      .not.toBe(originalColor);
    await expect
      .poll(() =>
        icon.evaluate((element) => {
          const matrix = new DOMMatrixReadOnly(getComputedStyle(element).transform);
          return matrix.m41 > 0 && matrix.m42 < 0;
        }),
      )
      .toBe(true);
    expect(
      await icon.evaluate((element) => parseFloat(getComputedStyle(element).transitionDuration)),
    ).toBeGreaterThan(0);

    await page.mouse.move(0, 0);
    await expect
      .poll(() => link.evaluate((element) => getComputedStyle(element).color))
      .toBe(originalColor);
    await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
    await link.focus();
    await expect(link).toBeFocused();
    await expect
      .poll(() => link.evaluate((element) => getComputedStyle(element).color))
      .not.toBe(originalColor);
    await expect
      .poll(() =>
        icon.evaluate((element) => {
          const matrix = new DOMMatrixReadOnly(getComputedStyle(element).transform);
          return matrix.m41 > 0 && matrix.m42 < 0;
        }),
      )
      .toBe(true);
  });

  test(`${path} reduced motion keeps arrows still with color feedback`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(path);
    const link = page.locator(".arrow-link").first();
    const originalColor = await link.evaluate((element) => getComputedStyle(element).color);
    await link.hover();
    await expect(link.locator(".arrow-link-icon")).toHaveCSS("transform", "none");
    await expect(link.locator(".arrow-link-icon")).toHaveCSS("transition-duration", "0s");
    await expect
      .poll(() => link.evaluate((element) => getComputedStyle(element).color))
      .not.toBe(originalColor);
  });
}
