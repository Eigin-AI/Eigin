import { test, expect } from "@playwright/test";
import { unlocalizedSections } from "../src/lib/unlocalized.ts";

for (const [preference, expected] of [
  ["da-DK", "da"],
  ["en-GB", "en"],
  ["de-DE", "en"],
]) {
  test(`language-free pages choose ${expected} for ${preference}`, async ({ browser, baseURL }) => {
    const context = await browser.newContext({ locale: preference, baseURL });
    try {
      const page = await context.newPage();
      for (const section of unlocalizedSections) {
        await page.goto(`/${section}/?source=shared#main`);
        await expect(page).toHaveURL(`${baseURL}/${expected}/${section}/?source=shared#main`);
        await expect(page.locator("html")).toHaveAttribute("lang", expected);
        await expect(page.locator("main")).toBeVisible();
      }
    } finally {
      await context.close();
    }
  });
}

test("language-free routes choose the first supported browser language", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "languages", { get: () => ["fr-FR", "da-DK", "en-GB"] });
  });
  await page.goto("/news/");
  await expect(page).toHaveURL(/\/da\/news\/$/);
});

test("language-free routes offer usable static links without JavaScript", async ({
  browser,
  baseURL,
}) => {
  const context = await browser.newContext({ javaScriptEnabled: false, baseURL });
  try {
    const page = await context.newPage();
    expect((await page.goto("/roadmap/"))?.status()).toBe(200);
    await expect(page.getByRole("link", { name: "English", exact: true })).toHaveAttribute(
      "href",
      "/en/roadmap/",
    );
    await expect(page.getByRole("link", { name: "Dansk", exact: true })).toHaveAttribute(
      "href",
      "/da/roadmap/",
    );
    await page.getByRole("link", { name: "Dansk", exact: true }).click();
    await expect(page).toHaveURL(/\/da\/roadmap\/$/);
  } finally {
    await context.close();
  }
});

test("language-free entry documents have a localized canonical and stay out of search", async ({
  request,
}) => {
  const response = await request.get("/news/");
  expect(response.status()).toBe(200);
  const html = await response.text();
  expect(html).toContain('name="eigin:locale-path" content="news/"');
  expect(html).toContain('name="robots" content="noindex, follow"');
  expect(html).toMatch(/rel="canonical" href="https:\/\/eigin.ai\/en\/news\/"/);
});

test("unknown paths and unsupported explicit languages remain 404s", async ({ request }) => {
  for (const path of [
    "/unknown/",
    "/fr/news/",
    "/news/missing-post/",
    "/trust/extra/",
    "/news/nested/missing/",
  ]) {
    expect((await request.get(path)).status(), path).toBe(404);
  }
});

test("an explicit article language still overrides browser preference", async ({
  browser,
  baseURL,
}) => {
  const context = await browser.newContext({ locale: "da-DK", baseURL });
  try {
    const page = await context.newPage();
    await page.goto("/en/news/introducing-eigin/");
    await expect(page).toHaveURL(/\/en\/news\/introducing-eigin\/$/);
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
  } finally {
    await context.close();
  }
});

test("language-free article links preserve the slug, query, and fragment", async ({
  browser,
  baseURL,
}) => {
  const context = await browser.newContext({ locale: "da-DK", baseURL });
  try {
    const page = await context.newPage();
    await page.goto("/news/introducing-eigin?source=shared#main");
    await expect(page).toHaveURL(`${baseURL}/da/news/introducing-eigin/?source=shared#main`);
    await expect(page.locator("article h1")).toContainText("Her er Eigin");
    await page.goto("/en/news/");
    await page.goBack();
    await expect(page).toHaveURL(`${baseURL}/da/news/introducing-eigin/?source=shared#main`);
  } finally {
    await context.close();
  }
});
