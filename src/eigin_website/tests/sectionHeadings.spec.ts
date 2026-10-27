import { expect, test } from "@playwright/test";

for (const locale of ["en", "da"]) {
  test(`${locale} section arrows share the same responsive visibility`, async ({ page }) => {
    for (const route of ["roadmap", "trust", "contact"]) {
      await page.goto(`/${locale}/${route}/`);
      await page.evaluate(() => document.fonts.ready);
      const arrows = page.locator(".section-heading-icon");
      await expect(arrows).toHaveCount(route === "contact" ? 1 : 3);
      for (const width of [1440, 1200, 1199, 1024, 768, 390, 320]) {
        await page.setViewportSize({ width, height: 1000 });
        for (const arrow of await arrows.all()) {
          await expect(arrow).toHaveAttribute("aria-hidden", "true");
          if (width >= 1200) await expect(arrow).toBeVisible();
          else await expect(arrow).toBeHidden();
        }
        await expect
          .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
          .toBe(true);
      }
    }
  });
}
