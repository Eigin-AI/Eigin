import { expect, test } from "@playwright/test";

test.use({ javaScriptEnabled: false });

for (const locale of ["en", "da"] as const) {
  test(`${locale} pages expose complete metadata before JavaScript`, async ({ page }) => {
    for (const [path, title] of [
      ["", "Eigin"],
      ["trust/", `${locale === "en" ? "Trust" : "Tillid"} · Eigin`],
      ["roadmap/", "Roadmap · Eigin"],
      ["contact/", `${locale === "en" ? "Contact" : "Kontakt"} · Eigin`],
      ["support/", "Support · Eigin"],
      ["privacy/", "Privacy Policy · Eigin"],
      ["terms/", "Terms of Service · Eigin"],
    ]) {
      await page.goto(`/${locale}/${path}`);
      await expect(page).toHaveTitle(title);
      await expect(page.locator("head title")).toHaveCount(1);
      const canonical = `https://eigin.ai/${locale}/${path}`;
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href", canonical);
      await expect(page.locator('meta[property="og:url"]')).toHaveAttribute("content", canonical);
      await expect(page.locator('meta[property="og:title"]')).toHaveAttribute("content", title);
      const description = await page.locator('meta[name="description"]').getAttribute("content");
      expect(description?.length).toBeGreaterThan(10);
      await expect(page.locator('meta[property="og:description"]')).toHaveAttribute(
        "content",
        description!,
      );
      await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
        "content",
        "summary_large_image",
      );
      await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
        "content",
        `https://eigin.ai/social/${locale}.png`,
      );
      await expect(page.locator('meta[property="og:locale"]')).toHaveAttribute(
        "content",
        locale === "en" ? "en_GB" : "da_DK",
      );
      for (const alternate of ["en", "da"]) {
        await expect(
          page.locator(`link[rel="alternate"][hreflang="${alternate}"]`),
        ).toHaveAttribute("href", `https://eigin.ai/${alternate}/${path}`);
      }
    }
  });
}

test("root URL has a branded preview without following its language redirect", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveTitle("Eigin");
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href", "https://eigin.ai/");
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
    "content",
    "https://eigin.ai/social/en.png",
  );
  await expect(page.locator('meta[property="og:image:alt"]')).toHaveAttribute("content", /Eigin/);
});

test("favicon and localized social image URLs serve valid image assets", async ({
  page,
  request,
}) => {
  await page.goto("/en/");
  const svg = await page.locator('link[rel="icon"][type="image/svg+xml"]').getAttribute("href");
  const icon = await request.get(svg!);
  expect(icon.ok()).toBe(true);
  expect(icon.headers()["content-type"]).toContain("image/svg+xml");
  expect(await icon.text()).toContain("<path");
  for (const [path, width, height] of [
    ["/favicon-32.png", 32, 32],
    ["/apple-touch-icon.png", 180, 180],
    ["/social/en.png", 1200, 630],
    ["/social/da.png", 1200, 630],
  ] as const) {
    const response = await request.get(path);
    expect(response.ok()).toBe(true);
    expect(response.headers()["content-type"]).toContain("image/png");
    const png = await response.body();
    expect(png.subarray(0, 8).toString("hex")).toBe("89504e470d0a1a0a");
    expect(png.readUInt32BE(16)).toBe(width);
    expect(png.readUInt32BE(20)).toBe(height);
  }
});
