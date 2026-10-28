import { test, expect } from "@playwright/test";

for (const locale of ["en", "da"]) {
  test(`${locale} footer controls fit and the language picker opens upward`, async ({ page }) => {
    await page.goto(`/${locale}/trust/`);
    const controls = page.locator(".footer-controls");
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      const box = (await controls.boundingBox())!;
      expect(box.x).toBeGreaterThanOrEqual(0);
      expect(box.x + box.width).toBeLessThanOrEqual(width);
    }
    const socials = page.locator(".social-links a");
    await expect(socials).toHaveCount(4);
    for (const [index, label] of ["LinkedIn", "Matrix", "GitLab", "GitHub"].entries()) {
      await expect(socials.nth(index)).toHaveAccessibleName(label);
    }
    const trigger = page.locator("footer .picker-trigger");
    await trigger.scrollIntoViewIfNeeded();
    await trigger.focus();
    await page.keyboard.press("Enter");
    await expect(trigger).toHaveAttribute("aria-expanded", "true");
    const panel = page.locator("footer .picker-panel");
    await expect(panel).toHaveAttribute("data-placement", /^top/);
    await expect(panel.locator(`a[hreflang="${locale}"]`)).toHaveAttribute("aria-current", "page");
    await page.keyboard.press("Escape");
    await expect(trigger).toBeFocused();
    await expect(trigger).toHaveAttribute("aria-expanded", "false");
    await trigger.click();
    const next = locale === "en" ? "da" : "en";
    await panel.locator(`a[hreflang="${next}"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${next}/trust/$`));
  });
}
