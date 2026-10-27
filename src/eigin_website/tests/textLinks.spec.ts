import { test, expect, type Locator, type Page } from "@playwright/test";

async function expectFeedback(link: Locator, page: Page, browserName: string) {
  const color = () => link.evaluate((element) => getComputedStyle(element).color);
  const alpha = () =>
    link.evaluate((element) => {
      const channels = getComputedStyle(element)
        .color.match(/[\d.]+/g)!
        .map(Number);
      return channels[3] ?? 1;
    });
  const restingColor = await color();
  await expect(link).toHaveCSS("filter", "none");
  expect(
    await link.evaluate((element) => parseFloat(getComputedStyle(element).transitionDuration)),
  ).toBeGreaterThan(0);
  await link.hover();
  await expect.poll(color).not.toBe(restingColor);
  await expect.poll(alpha).toBeLessThan(1);
  await expect(link).toHaveCSS("filter", "none");
  await page.mouse.move(0, 0);
  await expect.poll(color).toBe(restingColor);
  await expect(link).toHaveCSS("filter", "none");
  await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
  await link.focus();
  await expect.poll(color).not.toBe(restingColor);
  await expect.poll(alpha).toBeLessThan(1);
  await expect(link).toHaveCSS("filter", "none");
  await link.evaluate((element) => (element as HTMLAnchorElement).blur());
  await expect.poll(color).toBe(restingColor);
  await expect(link).toHaveCSS("filter", "none");
}

for (const locale of ["en", "da"]) {
  test(`${locale} text links animate color on hover and keyboard focus`, async ({
    page,
    browserName,
  }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.goto(`/${locale}/`);
    const desktopLink = page.locator(".desktop-nav a").first();
    if (await desktopLink.isVisible()) {
      await expectFeedback(desktopLink, page, browserName);
    } else {
      const summary = page.locator(".mobile-menu .picker-trigger");
      await summary.click();
      await expectFeedback(page.locator(".picker-panel a.picker-row").first(), page, browserName);
      await summary.click();
    }
    for (const selector of [".footer-links a", ".language-links a", ".social-links a"]) {
      await expectFeedback(page.locator(selector).first(), page, browserName);
    }
  });
}

test("text links change color without animation under reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/en/");
  const link = page.locator(".language-links a").first();
  const restingColor = await link.evaluate((element) => getComputedStyle(element).color);
  await link.hover();
  await expect(link).toHaveCSS("transition-duration", "0s");
  await expect(link).toHaveCSS("filter", "none");
  await expect
    .poll(() => link.evaluate((element) => getComputedStyle(element).color))
    .not.toBe(restingColor);
});
