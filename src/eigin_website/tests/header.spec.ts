import { expect, test } from "@playwright/test";

for (const locale of ["en", "da"]) {
  test(`${locale} header keeps text navigation until the smallest layout`, async ({ page }) => {
    await page.goto(`/${locale}/`);
    await page.evaluate(() => document.fonts.ready);
    const header = page.locator(".site-header");
    const navigation = header.locator(".desktop-nav");
    const menu = header.locator(".mobile-menu");
    const cta = header.locator(".header-cta");

    for (const width of [320, 375, 600, 601, 640, 767, 768, 820, 1024, 1199, 1200, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      if (width <= 600) {
        await expect(navigation).toBeHidden();
        await expect(menu).toBeVisible();
      } else {
        await expect(navigation).toBeVisible();
        await expect(menu).toBeHidden();
        const fit = await header.evaluate((element) => {
          const brand = element.querySelector(".site-brand")!.getBoundingClientRect();
          const nav = element.querySelector(".desktop-nav")!;
          const box = nav.getBoundingClientRect();
          const actions = element.querySelector(".header-actions")!.getBoundingClientRect();
          return {
            brandGap: box.left - brand.right,
            actionGap: actions.left - box.right,
            rightClearance: innerWidth - actions.right,
            singleLine: [...nav.querySelectorAll("a")].every((link) => {
              const range = document.createRange();
              range.selectNodeContents(link);
              return range.getClientRects().length === 1;
            }),
          };
        });
        expect(fit.brandGap).toBeGreaterThanOrEqual(16);
        expect(fit.actionGap).toBeGreaterThanOrEqual(16);
        expect(fit.rightClearance).toBeGreaterThanOrEqual(24);
        expect(fit.singleLine).toBe(true);
      }
      if (width >= 768) await expect(cta).toBeVisible();
      else await expect(cta).toBeHidden();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
    }

    await page.setViewportSize({ width: 601, height: 900 });
    await navigation.locator('a[href$="#teams"]').click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/#teams$`));

    await page.setViewportSize({ width: 600, height: 900 });
    const trigger = menu.locator(".picker-trigger");
    await trigger.focus();
    await page.keyboard.press("Enter");
    await expect(trigger).toHaveAttribute("aria-expanded", "true");
    await menu.locator('a[href$="#get"]').click();
    await expect(trigger).toHaveAttribute("aria-expanded", "false");
    await expect(page).toHaveURL(new RegExp(`/${locale}/#get$`));
  });
}
