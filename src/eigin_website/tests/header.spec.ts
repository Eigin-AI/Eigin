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

test("edge-to-edge backgrounds keep content within simulated phone safe areas", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const viewport of [
    { width: 390, height: 844 },
    { width: 844, height: 390 },
  ]) {
    await page.setViewportSize(viewport);
    await page.goto("/en/");
    // Browser emulation reports zero hardware insets; supply them at that boundary.
    await page.addStyleTag({
      content: `:root {
      --site-safe-top: 47px;
      --site-safe-left: 47px;
      --site-safe-right: 47px;
      --site-safe-bottom: 47px;
    }`,
    });
    const header = (await page.locator(".site-header").boundingBox())!;
    expect(header.x).toBe(0);
    expect(header.width).toBe(viewport.width);
    const brand = (await page.locator("header .site-brand").boundingBox())!;
    expect(brand.x).toBeGreaterThanOrEqual(47);
    expect(brand.y).toBeGreaterThanOrEqual(47);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(viewport.width);
    const content = await page.locator(".container").evaluateAll((elements) =>
      elements.map((element) => {
        const bounds = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return {
          left: bounds.left + parseFloat(style.paddingLeft),
          right: bounds.right - parseFloat(style.paddingRight),
        };
      }),
    );
    for (const bounds of content) {
      expect(bounds.left).toBeGreaterThanOrEqual(47);
      expect(bounds.right).toBeLessThanOrEqual(viewport.width - 47);
    }
    const section = (await page.locator("#personal").boundingBox())!;
    expect(section.x).toBe(0);
    expect(section.width).toBe(viewport.width);
    await page.evaluate(() => document.querySelector("#personal")!.scrollIntoView());
    await expect
      .poll(async () => (await page.locator("#personal").boundingBox())!.y)
      .toBeGreaterThanOrEqual(header.height - 1);
    expect(
      await page
        .locator(".footer-inner")
        .evaluate((el) => parseFloat(getComputedStyle(el).paddingBottom)),
    ).toBeGreaterThanOrEqual(47);
  }
});

test("header blends into the page canvas while retaining its frosted surface", async ({ page }) => {
  await page.goto("/en/");
  await page.locator("#get").scrollIntoViewIfNeeded();
  const surface = await page.locator(".site-header").evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      canvas: getComputedStyle(document.documentElement).backgroundColor,
      blend: style.backgroundImage,
      blur: style.backdropFilter || style.getPropertyValue("-webkit-backdrop-filter"),
      supportsBlur:
        CSS.supports("backdrop-filter", "blur(16px)") ||
        CSS.supports("-webkit-backdrop-filter", "blur(16px)"),
    };
  });
  expect(surface.blend).toContain(surface.canvas);
  if (surface.supportsBlur) expect(surface.blur).toContain("blur(");
});
