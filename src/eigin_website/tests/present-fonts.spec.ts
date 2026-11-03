import { expect, test } from "@playwright/test";

test("NorthEast headings and SVG text use the centered E glyph by default", async ({ page }) => {
  await page.route(
    (url) => url.pathname === "/font.md",
    (route) =>
      route.fulfill({
        body: '# EEE\n\n<svg width="300" height="100" viewBox="0 0 300 100"><text x="0" y="80" font-size="80" font-family="NorthEastCN" font-weight="700">EEE</text></svg>',
      }),
  );
  await page.goto("/present/render/?src=/font.md&slide=1");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  for (const selector of ["h1", "svg"]) {
    const glyphs = page.frameLocator("iframe").locator(selector);
    const original = await glyphs.screenshot();
    await glyphs.evaluate((element) => {
      (element as HTMLElement | SVGElement).style.fontFeatureSettings = '"ss01" 1';
    });
    expect(await glyphs.screenshot()).toEqual(original);
    await glyphs.evaluate((element) => {
      (element as HTMLElement | SVGElement).style.fontFeatureSettings = '"ss01" 0';
    });
    expect(await glyphs.screenshot()).not.toEqual(original);
  }
});
