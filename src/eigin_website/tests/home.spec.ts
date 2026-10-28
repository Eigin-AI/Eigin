import { test, expect } from "@playwright/test";

for (const locale of ["en", "da"]) {
  test(`${locale} renders without JavaScript`, async ({ browser, baseURL }) => {
    const context = await browser.newContext({ javaScriptEnabled: false, baseURL });
    const page = await context.newPage();
    await page.goto(`/${locale}/`);
    await expect(page.locator("html")).toHaveAttribute("lang", locale);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByRole("main")).toBeVisible();
    const next = locale === "en" ? "da" : "en";
    await page.locator("footer .language-links .picker-trigger").click();
    await page.locator(`footer a[hreflang="${next}"]`).click();
    await expect(page.locator("html")).toHaveAttribute("lang", next);
    await context.close();
  });
}

for (const [preference, expected] of [
  ["da-DK", "da"],
  ["en-GB", "en"],
  ["de-DE", "en"],
]) {
  test(`root chooses ${expected} for ${preference}`, async ({ browser, baseURL }) => {
    const context = await browser.newContext({ locale: preference, baseURL });
    const page = await context.newPage();
    await page.goto("/");
    await expect(page).toHaveURL(new RegExp(`/${expected}/$`));
    await context.close();
  });
}

test("footer language links respect explicit choice and keyboard navigation", async ({
  page,
  browserName,
}) => {
  await page.goto("/en/");
  // WebKit follows the platform's full keyboard access setting for links.
  await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
  await expect(page.locator('a[href="#main"]')).toBeFocused();
  await page.locator("footer .language-links .picker-trigger").click();
  const danish = page.locator('footer a[hreflang="da"]');
  await danish.focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/da\/$/);
  await expect(page.locator("html")).toHaveAttribute("lang", "da");
  await page.locator("footer .language-links .picker-trigger").click();
  await expect(page.locator('footer a[hreflang="da"]')).toHaveAttribute("aria-current", "page");
  await expect(page.locator('footer a[hreflang="en"]')).not.toHaveAttribute("aria-current");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
});

for (const scheme of ["light", "dark"] as const) {
  test(`responsive layout under ${scheme} system preference`, async ({ page }) => {
    await page.emulateMedia({ colorScheme: scheme, reducedMotion: "reduce" });
    await page.goto("/da/");
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
    const background = await page
      .locator(".eigin-root")
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(background).not.toBe("rgba(0, 0, 0, 0)");
    await page.screenshot({ path: test.info().outputPath(`${scheme}.png`), fullPage: true });
  });
}

test("unsupported locale returns 404", async ({ page }) => {
  const response = await page.goto("/de/");
  expect(response?.status()).toBe(404);
});

test("an explicit locale overrides browser preference", async ({ browser, baseURL }) => {
  const context = await browser.newContext({ locale: "da-DK", baseURL });
  const page = await context.newPage();
  await page.goto("/en/");
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect(page).toHaveURL(/\/en\/$/);
  await context.close();
});

test("root selects the first supported browser language", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "languages", { get: () => ["de-DE", "da-DK", "en-GB"] });
  });
  await page.goto("/");
  await expect(page).toHaveURL(/\/da\/$/);
});

test("section palettes stay fixed when system preference changes", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto("/en/");
  const colors = () =>
    page
      .locator(
        ".site-header, main > section, .site-footer, .hero-title, .hero-bottom > p, .hero-cta a",
      )
      .evaluateAll((elements) =>
        elements.map((element) => {
          const style = getComputedStyle(element);
          return { background: style.backgroundColor, color: style.color };
        }),
      );
  const initial = await colors();
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
  expect(await colors()).toEqual(initial);
});

for (const locale of ["en", "da"]) {
  test(`${locale} navigation and calls to action work`, async ({ page }) => {
    await page.goto(`/${locale}/`);
    const mobileMenu = page.locator(".mobile-menu");
    const compactHeader = await mobileMenu.isVisible();
    if (compactHeader) await mobileMenu.locator(".picker-trigger").click();
    const navigation = compactHeader ? mobileMenu : page.locator(".desktop-nav");
    await navigation.locator('a[href$="#teams"]').click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/#teams$`));
    if (compactHeader)
      await expect(mobileMenu.locator(".picker-trigger")).toHaveAttribute("aria-expanded", "false");
    await expect(page.locator("#teams")).toBeInViewport();
    await page.locator('.hero a[href="#get"]').click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/#get$`));
    await expect(page.locator('#get a[href^="https://apps.apple.com"]').first()).toBeVisible();
  });
}

test("in-page navigation has valid destinations", async ({ page }) => {
  await page.goto("/en/");
  const missing = await page
    .locator('a[href^="#"]')
    .evaluateAll((links) =>
      links
        .map((link) => link.getAttribute("href")!)
        .filter((href) => !document.getElementById(href.slice(1))),
    );
  expect(missing).toEqual([]);
});

test("footer language links fit within the viewport", async ({ page }) => {
  await page.goto("/en/");
  const links = page.locator("footer .language-links");
  await links.scrollIntoViewIfNeeded();
  const box = (await links.boundingBox())!;
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(page.viewportSize()!.width);
});

test("header, page content, and footer share the horizontal grid", async ({ page }) => {
  await page.goto("/en/");
  for (const width of [375, 768, 1280, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    const logo = (await page.locator("header .site-brand").boundingBox())!;
    const headline = (await page.locator("h1").boundingBox())!;
    const footerLogo = (await page.locator("footer .site-brand").boundingBox())!;
    expect(logo.x).toBeCloseTo(headline.x, 0);
    expect(logo.x).toBeCloseTo(footerLogo.x, 0);
    const header = (await page.locator(".header-inner").boundingBox())!;
    const content = (await page.locator(".hero-inner").boundingBox())!;
    expect(header.x).toBeCloseTo(content.x, 0);
    expect(header.width).toBeCloseTo(content.width, 0);
  }
});

test("team and privacy headings share typography with readable local text", async ({ page }) => {
  await page.goto("/en/");
  const typography = (selector: string) =>
    page.locator(selector).evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        family: style.fontFamily,
        weight: style.fontWeight,
        size: style.fontSize,
        lineHeight: style.lineHeight,
      };
    });
  expect(await typography("#privacy-title")).toEqual(await typography("#teams-title"));
  const contrast = await page.locator("#private").evaluate((section) => {
    const luminance = (color: string) => {
      const channels = color
        .match(/[\d.]+/g)!
        .slice(0, 3)
        .map((value) => {
          const channel = Number(value) / 255;
          return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
        });
      return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    };
    const foreground = luminance(getComputedStyle(section.querySelector(".section-title")!).color);
    const background = luminance(getComputedStyle(section).backgroundColor);
    return (Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05);
  });
  expect(contrast).toBeGreaterThanOrEqual(4.5);
});

test("hero supporting text has readable contrast", async ({ page }) => {
  await page.goto("/en/");
  const contrast = await page.locator(".hero-bottom > p").evaluate((lead) => {
    const luminance = (color: string) => {
      const channels = color
        .match(/[\d.]+/g)!
        .slice(0, 3)
        .map((value) => {
          const channel = Number(value) / 255;
          return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
        });
      return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    };
    const foreground = luminance(getComputedStyle(lead).color);
    const background = luminance(getComputedStyle(lead.closest(".hero")!).backgroundColor);
    return (Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05);
  });
  expect(contrast).toBeGreaterThanOrEqual(4.5);
});

test("mobile menu CTA closes the menu and reaches its destination", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  for (const locale of ["en", "da"]) {
    await page.goto(`/${locale}/`);
    const menu = page.locator(".mobile-menu");
    await menu.locator(".picker-trigger").click();
    await expect(menu.locator(".picker-trigger")).toHaveAttribute("aria-expanded", "true");
    await menu.locator(".eigin-btn").click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/#get$`));
    await expect(menu.locator(".picker-trigger")).toHaveAttribute("aria-expanded", "false");
    await expect(page.locator("#get")).toBeInViewport();
  }
});

test("hero supporting text uses the larger light serif lead", async ({ page }) => {
  await page.goto("/en/");
  const lead = page.locator(".hero-bottom > p");
  await expect(lead).toHaveCSS("font-size", "24px");
  await expect
    .poll(() => lead.evaluate((element) => parseFloat(getComputedStyle(element).lineHeight)))
    .toBeCloseTo(28.8, 1);
  await expect(lead).toHaveCSS("font-weight", "300");
});

test("feature copy and promises share the same grid", async ({ page }) => {
  for (const locale of ["en", "da"]) {
    await page.goto(`/${locale}/`);
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      const feature = (await page.locator("#personal .feature-copy").boundingBox())!;
      const promises = (await page.locator(".promises").boundingBox())!;
      expect(feature.x).toBeCloseTo(promises.x, 0);
      if (width >= 1200) {
        const quarter = (await page.locator(".promises > div").first().boundingBox())!;
        const gutter = await page
          .locator(".promises")
          .evaluate((element) => parseFloat(getComputedStyle(element).columnGap));
        expect(feature.width).toBeCloseTo(quarter.width * 2 + gutter, 0);
      }
      const introduction = await page
        .locator("#personal .section-intro")
        .evaluate((element) => getComputedStyle(element).fontSize);
      await expect(page.locator("#personal .feature-list")).toHaveCSS("font-size", introduction);
    }
  }
});

for (const locale of ["en", "da"]) {
  test(`${locale} pricing links lead to downloads, questions and email enquiries`, async ({
    page,
  }) => {
    await page.goto(`/${locale}/`);
    const pricing = page.locator("#pricing");
    await pricing.locator(".section-heading a").click();
    await expect(page).toHaveURL(/#faq$/);
    const plans = pricing.locator("a.plan");
    await expect(plans).toHaveCount(4);
    await plans.nth(0).click();
    await expect(page).toHaveURL(/#get$/);
    await plans.nth(1).click();
    await expect(page).toHaveURL(/#faq$/);
    const teamHref =
      locale === "en"
        ? "mailto:hello@eigin.ai?subject=Eigin%20for%20teams%20early%20access"
        : "mailto:hello@eigin.ai?subject=Eigin%20til%20teams%20early%20access";
    await expect(plans.nth(2)).toHaveAttribute("href", teamHref);
    await expect(page.locator('#faq a[href*="early%20access"]')).toHaveAttribute("href", teamHref);
    await expect(plans.nth(3)).toHaveAttribute(
      "href",
      locale === "en"
        ? "mailto:hello@eigin.ai?subject=Eigin%20for%20organisations"
        : "mailto:hello@eigin.ai?subject=Eigin%20til%20organisationer",
    );
  });
}

test("root selects a language before application JavaScript loads and preserves the destination", async ({
  page,
}) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "languages", { get: () => ["de-DE", "da-DK", "en-GB"] });
  });
  await page.route("**/*", (route) => {
    const request = route.request();
    return request.resourceType() === "script" ? route.abort() : route.continue();
  });
  await page.goto("/?source=test#pricing");
  await expect(page).toHaveURL(/\/da\/\?source=test#pricing$/);
  await expect(page.locator("html")).toHaveAttribute("lang", "da");
  await expect(page.locator("#pricing")).toBeVisible();
});

test("root offers both languages without JavaScript", async ({ browser, baseURL }) => {
  const context = await browser.newContext({ javaScriptEnabled: false, baseURL });
  try {
    const page = await context.newPage();
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Eigin", exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "English", exact: true })).toBeVisible();
    await page.getByRole("link", { name: "Dansk", exact: true }).click();
    await expect(page).toHaveURL(/\/da\/$/);
  } finally {
    await context.close();
  }
});
