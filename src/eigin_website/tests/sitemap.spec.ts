import { test, expect } from "@playwright/test";
import social from "../src/lib/content/social.json" with { type: "json" };
import { unlocalizedSections } from "../src/lib/unlocalized.ts";
import { locales } from "../src/lib/locales.ts";

async function parseSitemap(page: import("@playwright/test").Page, xml: string) {
  return page.evaluate((xml) => {
    const document = new DOMParser().parseFromString(xml, "application/xml");
    return {
      errors: document.querySelectorAll("parsererror").length,
      namespace: document.documentElement.namespaceURI,
      urls: [...document.querySelectorAll("url > loc")].map((loc) => loc.textContent!),
    };
  }, xml);
}

test("static sitemap lists canonical public pages with working links", async ({
  page,
  request,
}) => {
  const response = await request.get("/sitemap.xml");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("xml");
  const sitemap = await parseSitemap(page, await response.text());
  expect(sitemap.errors).toBe(0);
  expect(sitemap.namespace).toBe("http://www.sitemaps.org/schemas/sitemap/0.9");
  expect(new Set(sitemap.urls).size).toBe(sitemap.urls.length);
  for (const locale of locales) {
    for (const path of ["", ...unlocalizedSections.map((section) => `${section}/`)]) {
      expect(sitemap.urls).toContain(`${social.origin}/${locale}/${path}`);
    }
  }
  for (const url of sitemap.urls) {
    expect(url).toMatch(new RegExp(`^${social.origin}/(en|da)/`));
    expect((await request.get(url.slice(social.origin.length))).status()).toBe(200);
  }
  for (const excluded of ["/news/", "/present/", "/news/introducing-eigin/"]) {
    expect(sitemap.urls).not.toContain(`${social.origin}${excluded}`);
  }
  for (const locale of locales) {
    expect(sitemap.urls).toContain(`${social.origin}/${locale}/news/introducing-eigin/`);
  }
});

test("robots advertises the sitemap and allows crawling", async ({ request }) => {
  const response = await request.get("/robots.txt");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("text/plain");
  expect(await response.text()).toBe(
    `User-agent: *\nAllow: /\n\nSitemap: ${social.origin}/sitemap.xml\n`,
  );
});

test("LLM guide links to available public product information", async ({ request }) => {
  const response = await request.get("/llms.txt");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("text/plain");
  const guide = await response.text();
  expect(guide).toMatch(/^# Eigin\n/);
  expect(guide).toMatch(/^> .+/m);
  const links = [...guide.matchAll(/\]\((https:\/\/[^)]+)\)/g)].map((match) => match[1]);
  expect(links.length).toBeGreaterThan(0);
  for (const link of links.filter((link) => link.startsWith(`${social.origin}/`))) {
    expect((await request.get(link.slice(social.origin.length))).status()).toBe(200);
  }
});
