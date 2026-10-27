import { test, expect } from "@playwright/test";
import { roadmapData } from "../src/lib/content/roadmap/data";

for (const locale of ["en", "da"] as const) {
  test(`${locale} roadmap prerenders data without JavaScript`, async ({ browser, baseURL }) => {
    const context = await browser.newContext({ javaScriptEnabled: false, baseURL });
    const page = await context.newPage();
    try {
      const response = await page.goto(`/${locale}/roadmap/`);
      expect(response?.status()).toBe(200);
      await expect(page.locator("html")).toHaveAttribute("lang", locale);
      await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);
      await expect(page.locator(".roadmap-status")).toHaveCount(3);
      await expect(page.locator(".roadmap-status-label p")).toHaveCount(0);
      await expect(page.locator('.section-heading-icon[aria-hidden="true"] svg')).toHaveCount(3);
      for (const item of [
        ...roadmapData.active,
        ...roadmapData.planned,
        ...roadmapData.launched.flatMap((release) => release.items),
      ]) {
        const entry = page.locator(`#roadmap-${item.id}`);
        const text = item.copy[locale] ?? item.copy.en;
        await expect(entry).toBeVisible();
        await expect(entry.locator("p")).toHaveCount(text.description ? 1 : 0);
        await expect(entry.locator(".roadmap-version")).toHaveCount(item.version ? 1 : 0);
        if (item.version) {
          await expect(entry.locator(".roadmap-version")).toHaveText(item.version.label);
          if (!item.version.href) {
            await expect(entry.locator("span.roadmap-version .t-tag")).toBeVisible();
            await expect(entry.locator(".roadmap-version")).not.toHaveAttribute("href");
            await expect(entry.getByRole("button")).toHaveCount(0);
          }
        }
      }
      await expect(page.locator(".roadmap-period")).toHaveCount(
        roadmapData.launched.filter((release) => release.period).length,
      );
      await page.evaluate(() => document.fonts.ready);
      const ios = (await page.locator("#roadmap-ios").boundingBox())!;
      const relay = (await page.locator("#roadmap-relay").boundingBox())!;
      expect(Math.abs(relay.y - ios.y - ios.height)).toBeLessThan(1);
      const next = locale === "en" ? "da" : "en";
      await page.locator(`footer a[hreflang="${next}"]`).click();
      await expect(page).toHaveURL(new RegExp(`/${next}/roadmap/$`));
      await expect(page.locator("html")).toHaveAttribute("lang", next);
    } finally {
      await context.close();
    }
  });

  test(`${locale} homepage navigation reaches the separate roadmap`, async ({ page }) => {
    await page.goto(`/${locale}/`);
    const menu = page.locator(".mobile-menu");
    const compact = await menu.isVisible();
    if (compact) await menu.locator(".picker-trigger").click();
    const navigation = compact ? menu : page.locator(".desktop-nav");
    await navigation.locator(`a[href="/${locale}/roadmap/"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/roadmap/$`));
    await expect(page.locator(".roadmap-page")).toBeVisible();
    const currentMenu = page.locator(".mobile-menu");
    if (compact) await currentMenu.locator(".picker-trigger").click();
    const currentNavigation = compact ? currentMenu : page.locator(".desktop-nav");
    await currentNavigation.locator(`a[href="/${locale}/#teams"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/#teams$`));
    await expect(page.locator("#teams")).toBeInViewport();
  });

  test(`${locale} roadmap locale switch preserves the page`, async ({ page }) => {
    await page.goto(`/${locale}/roadmap/`);
    const next = locale === "en" ? "da" : "en";
    await page.locator(`footer a[hreflang="${next}"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${next}/roadmap/$`));
    await expect(page.locator(`footer a[hreflang="${next}"]`)).toHaveAttribute(
      "aria-current",
      "page",
    );
    await expect(page.locator('head link[rel="alternate"][hreflang="en"]')).toHaveAttribute(
      "href",
      "/en/roadmap/",
    );
    await expect(page.locator('head link[rel="alternate"][hreflang="da"]')).toHaveAttribute(
      "href",
      "/da/roadmap/",
    );
  });
}

test("desktop status headings align with their first item and scroll with the page", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const locale of ["en", "da"]) {
    await page.goto(`/${locale}/roadmap/`);
    await page.evaluate(() => document.fonts.ready);
    const arrowPositions: number[] = [];
    for (const section of await page.locator(".roadmap-status").all()) {
      const label = (await section.locator(".roadmap-status-label h2").boundingBox())!;
      const item = (await section
        .locator(".roadmap-item-heading")
        .first()
        .getByRole("heading")
        .boundingBox())!;
      expect(Math.abs(label.y + label.height / 2 - item.y - item.height / 2)).toBeLessThan(1);
      arrowPositions.push((await section.locator(".section-heading-icon").boundingBox())!.x);
    }
    expect(Math.max(...arrowPositions) - Math.min(...arrowPositions)).toBeLessThan(1);
    for (const heading of await page.locator(".roadmap-item-heading:has(.roadmap-version)").all()) {
      const title = (await heading.getByRole("heading").boundingBox())!;
      const version = heading.locator(".roadmap-version");
      const tag = (await version.boundingBox())!;
      expect(Math.abs(title.y + title.height / 2 - tag.y - tag.height / 2)).toBeLessThan(1);
      const regularTagHeight = await version.evaluate((element) =>
        parseFloat(getComputedStyle(element).getPropertyValue("--sizing-button-height-tag")),
      );
      expect(tag.height).toBeLessThan(regularTagHeight);
    }
    const label = page.locator(".roadmap-status-label h2").nth(1);
    await label.evaluate((element) =>
      window.scrollTo({
        top: element.getBoundingClientRect().top + scrollY - 130,
        behavior: "instant",
      }),
    );
    const before = (await label.boundingBox())!;
    const beforeScroll = await page.evaluate(() => scrollY);
    await page.evaluate(() => window.scrollBy({ top: 80, behavior: "instant" }));
    const distance = (await page.evaluate(() => scrollY)) - beforeScroll;
    expect(distance).toBeGreaterThan(0);
    const after = (await label.boundingBox())!;
    expect(Math.abs(after.y - (before.y - distance))).toBeLessThan(1);
  }
});

for (const scheme of ["light", "dark"] as const) {
  test(`roadmap remains readable under ${scheme} system preference`, async ({ page }) => {
    await page.emulateMedia({ colorScheme: scheme, reducedMotion: "reduce" });
    await page.goto("/da/roadmap/");
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
    const wide = await page.evaluate(() => matchMedia("(min-width: 1200px)").matches);
    const arrow = page.locator(".section-heading-icon").first();
    if (wide) await expect(arrow).toBeVisible();
    else await expect(arrow).toBeHidden();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    const header = (await page.locator("header .site-brand").boundingBox())!;
    const title = (await page.locator(".roadmap-title").boundingBox())!;
    expect(header.x).toBeCloseTo(title.x, 0);
    await page.screenshot({ path: test.info().outputPath(`${scheme}.png`), fullPage: true });
  });
}

test("roadmap keyboard skip link and local destinations work", async ({ page, browserName }) => {
  await page.goto("/en/roadmap/");
  await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
  await expect(page.locator('a[href="#main"]')).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/en\/roadmap\/#main$/);
  const missing = await page
    .locator('a[href^="#"]')
    .evaluateAll((links) =>
      links
        .map((link) => link.getAttribute("href")!)
        .filter((href) => !document.getElementById(href.slice(1))),
    );
  expect(missing).toEqual([]);
});

test("roadmap respects an explicit locale and rejects unsupported locales", async ({
  browser,
  baseURL,
}) => {
  const context = await browser.newContext({ locale: "da-DK", baseURL });
  const page = await context.newPage();
  try {
    await page.goto("/en/roadmap/");
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
    expect((await page.goto("/de/roadmap/"))?.status()).toBe(404);
  } finally {
    await context.close();
  }
});
