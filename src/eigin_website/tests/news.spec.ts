import { test, expect } from "@playwright/test";
import social from "../src/lib/content/social.json" with { type: "json" };

for (const locale of ["en", "da"] as const) {
  test(`${locale} news and articles work without JavaScript`, async ({ browser, baseURL }) => {
    const context = await browser.newContext({ javaScriptEnabled: false, baseURL });
    const page = await context.newPage();
    try {
      expect((await page.goto(`/${locale}/news/`))?.status()).toBe(200);
      await expect(page.locator("html")).toHaveAttribute("lang", locale);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
        "href",
        `${social.origin}/${locale}/news/`,
      );
      await expect(page.locator('meta[property="og:type"]')).toHaveAttribute("content", "website");
      await expect(page.locator('meta[property="article:published_time"]')).toHaveCount(0);
      await expect(page.locator('link[type="application/rss+xml"]')).toHaveAttribute(
        "href",
        `/${locale}/news/rss.xml`,
      );
      await expect(page.locator('.news-intro a[href="mailto:hello@eigin.ai"]')).toBeVisible();
      await expect(page.locator(`footer a[href="/${locale}/news/"]:not([hreflang])`)).toBeVisible();
      await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);
      await expect(page.locator("article")).toBeVisible();
      const title = (await page.locator("article h2").textContent())!.trim();
      const date = await page.locator("article time").getAttribute("datetime");
      const mobileIndex = page.locator(".news-mobile-index");
      const mobile = await mobileIndex.isVisible();
      if (mobile) await mobileIndex.locator("summary").click();
      const navigation = mobile ? mobileIndex : page.locator(".news-sidebar");
      const first = navigation.locator("a").first();
      const path = (await first.getAttribute("href"))!;
      await expect(first).toHaveAttribute("aria-current", "page");
      await first.click();
      await expect(page).toHaveURL(`${baseURL}${path}`);
      await expect(page.locator("article h1")).toHaveText(title);
      await expect(page.locator(".news-prose p").first()).not.toBeEmpty();
      await expect(page.locator('meta[property="og:type"]')).toHaveAttribute("content", "article");
      await expect(page.locator('meta[property="article:published_time"]')).toHaveAttribute(
        "content",
        `${date}T00:00:00Z`,
      );
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
        "href",
        `${social.origin}${path}`,
      );
      const next = locale === "en" ? "da" : "en";
      const translated = path.replace(`/${locale}/`, `/${next}/`);
      await expect(page.locator(`link[hreflang="${next}"]`)).toHaveAttribute(
        "href",
        `${social.origin}${translated}`,
      );
      await page.locator("footer .language-links .picker-trigger").click();
      await page.locator(`footer a[hreflang="${next}"]`).click();
      await expect(page).toHaveURL(`${baseURL}${translated}`);
      await expect(page.locator("html")).toHaveAttribute("lang", next);
      await expect(page.locator("article h1")).not.toBeEmpty();
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
      ).toBe(true);
    } finally {
      await context.close();
    }
  });

  test(`${locale} RSS describes published articles`, async ({ page, request }) => {
    const response = await request.get(`/${locale}/news/rss.xml`);
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("xml");
    const parsed = await page.evaluate(
      (xml) => {
        const document = new DOMParser().parseFromString(xml, "application/xml");
        return {
          errors: document.querySelectorAll("parsererror").length,
          language: document.querySelector("language")?.textContent,
          items: [...document.querySelectorAll("item")].map((item) => ({
            title: item.querySelector("title")?.textContent,
            description: item.querySelector("description")?.textContent,
            link: item.querySelector("link")?.textContent,
            guid: item.querySelector("guid")?.textContent,
            date: item.querySelector("pubDate")?.textContent,
          })),
        };
      },
      await response.text(),
    );
    expect(parsed.errors).toBe(0);
    expect(parsed.language).toBe(locale);
    expect(parsed.items.length).toBeGreaterThan(0);
    const dates = parsed.items.map((item) => Date.parse(item.date!));
    expect(dates.every(Number.isFinite)).toBe(true);
    expect(dates).toEqual([...dates].sort((a, b) => b - a));
    await page.goto(`/${locale}/news/`);
    const paths = await page
      .locator(".news-sidebar a")
      .evaluateAll((links) => links.map((link) => link.getAttribute("href")));
    expect(parsed.items.map((item) => item.link!.replace(social.origin, ""))).toEqual(paths);
    for (const item of parsed.items) {
      expect(item.guid).toBe(item.link);
      expect(item.link).toContain(`${social.origin}/${locale}/news/`);
      expect((await page.goto(item.link!.replace(social.origin, "")))?.status()).toBe(200);
      await expect(page.locator("article h1")).toHaveText(item.title!);
      await expect(page.locator('meta[name="description"]')).toHaveAttribute(
        "content",
        item.description!,
      );
      const date = await page.locator("article time").getAttribute("datetime");
      expect(Date.parse(item.date!)).toBe(Date.parse(`${date}T00:00:00Z`));
    }
  });
}

test("news body typography matches the homepage", async ({ page }) => {
  const measure = async (selector: string) =>
    page
      .locator(selector)
      .first()
      .evaluate((element) => {
        const style = getComputedStyle(element);
        return {
          font: style.fontFamily,
          size: style.fontSize,
          weight: style.fontWeight,
          lineHeight: style.lineHeight,
        };
      });
  await page.goto("/en/");
  await page.evaluate(() => document.fonts.ready);
  const home = await measure(".promises h3 + p");
  await page.goto("/en/news/");
  await page.evaluate(() => document.fonts.ready);
  expect(await measure(".news-prose p")).toEqual(home);
});

test("RSS link loads the feed outside the article router", async ({ page }) => {
  await page.goto("/en/news/");
  const link = page.locator('main a[href="/en/news/rss.xml"]');
  await expect(link).toHaveAttribute("data-sveltekit-reload", "");
  // RSS may download or open the browser’s XML viewer. Both require a document request.
  const response = page.waitForResponse(
    (response) =>
      response.url().endsWith("/en/news/rss.xml") && response.request().isNavigationRequest(),
  );
  await link.click({ noWaitAfter: true });
  const feed = await response;
  expect(feed.status()).toBe(200);
  expect(feed.headers()["content-type"]).toContain("xml");
});

test("article navigation supports keyboard input and browser history", async ({
  page,
  baseURL,
}) => {
  await page.goto("/en/news/");
  const link = page.locator("article h2 a");
  const path = await link.getAttribute("href");
  const title = (await link.textContent())!.trim();
  await link.focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(`${baseURL}${path}`);
  await expect(page.locator("article h1")).toHaveText(title);
  await page.goBack();
  await expect(page).toHaveURL(`${baseURL}/en/news/`);
  await expect(page.locator("article h2 a")).toHaveText(title);
  await page.goForward();
  await expect(page).toHaveURL(`${baseURL}${path}`);
  await expect(page.locator("article h1")).toHaveText(title);
});

test("unknown news articles and locales return 404", async ({ request }) => {
  expect((await request.get("/en/news/missing-post/")).status()).toBe(404);
  expect((await request.get("/fr/news/")).status()).toBe(404);
});
