import { expect, test } from "@playwright/test";

const deck = "# First\n\n---\n\n## Second\n";
const image =
  '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="12"/></svg>';

test("closing a local deck returns to a usable launcher", async ({ page }) => {
  await page.goto("/present/");
  await expect(page.locator('input[type="file"]')).toBeEnabled();
  await page
    .locator('input[type="file"]')
    .setInputFiles({ name: "deck.md", mimeType: "text/plain", buffer: Buffer.from(deck) });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  await page.getByRole("link", { name: "Close presentation" }).click();
  await expect(page.getByRole("heading", { name: "Ready to present.", exact: true })).toBeVisible();
  await expect(page.locator("iframe")).toHaveCount(0);
  await expect(page.locator('input[type="file"]')).toBeEnabled();
  await page
    .locator('input[type="file"]')
    .setInputFiles({ name: "next.md", mimeType: "text/plain", buffer: Buffer.from("# Next deck") });
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "Next deck" }),
  ).toBeVisible();
});

test("error recovery link resets a rejected local file", async ({ page }) => {
  await page.goto("/present/");
  await expect(page.locator('input[type="file"]')).toBeEnabled();
  await page.locator('input[type="file"]').setInputFiles({
    name: "unsupported.exe",
    mimeType: "application/octet-stream",
    buffer: Buffer.from("invalid"),
  });
  await expect(page.getByRole("alert")).toBeVisible();
  await page.getByRole("link", { name: "Open another deck" }).click();
  await expect(page.getByRole("heading", { name: "Ready to present.", exact: true })).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
  expect(new URL(page.url()).search).toBe("");
});

test("watched source recovers when its initial 404 becomes available", async ({ page }) => {
  let available = false;
  await page.route(
    (url) => url.pathname === "/later.md",
    (route) => route.fulfill(available ? { body: deck } : { status: 404 }),
  );
  await page.goto("/present/render/?src=/later.md");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "error");
  available = true;
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "First", exact: true }),
  ).toBeVisible();
});

test("watch retries an image without a Markdown edit", async ({ page }) => {
  let available = false;
  await page.route(
    (url) => url.pathname === "/images.md",
    (route) => route.fulfill({ body: "# Image\n\n![Example](/later.svg)" }),
  );
  await page.route(
    (url) => url.pathname === "/later.svg",
    (route) =>
      route.fulfill(available ? { body: image, contentType: "image/svg+xml" } : { status: 404 }),
  );
  await page.goto("/present/render/?src=/images.md");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "error");
  available = true;
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.frameLocator("iframe").getByRole("img", { name: "Example" })).toBeVisible();
});

test("fullscreen menu remains pointer-accessible and supports keyboard reopening", async ({
  page,
  browserName,
  isMobile,
}) => {
  test.skip(
    browserName !== "chromium" || isMobile,
    "Desktop Chromium supports automated fullscreen.",
  );
  await page.goto("/present/");
  await expect(page.locator('input[type="file"]')).toBeEnabled();
  await page
    .locator('input[type="file"]')
    .setInputFiles({ name: "deck.md", mimeType: "text/plain", buffer: Buffer.from(deck) });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  await page.getByRole("button", { name: "Fullscreen", exact: true }).click();
  await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(true);
  await expect(page.getByRole("button", { name: "Menu", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  await expect(page.getByRole("navigation", { name: "Presentation actions" })).toBeVisible();
  await page.keyboard.press("Escape");
  await page.keyboard.press("m");
  await expect(page.getByRole("navigation", { name: "Presentation actions" })).toBeVisible();
  await page.getByRole("button", { name: "Fullscreen", exact: true }).click();
  await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(false);
});

for (const route of ["/present/render/"]) {
  test(`${route} watch=0 stops source polling after readiness`, async ({ page }) => {
    await page.clock.install();
    let requests = 0;
    await page.route(
      (url) => url.pathname === "/static.md",
      (route) => {
        requests++;
        return route.fulfill({ body: requests === 1 ? "# Original" : "# Replaced" });
      },
    );
    await page.goto(`${route}?src=/static.md&watch=0`);
    await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
    await page.clock.runFor(3100);
    expect(requests).toBe(1);
    await expect(
      page.frameLocator("iframe").getByRole("heading", { name: "Original" }),
    ).toBeVisible();
  });
}

for (const reducedMotion of ["reduce", "no-preference"] as const) {
  test(`slide changes are instant with ${reducedMotion}, regardless of transition settings`, async ({
    page,
  }) => {
    await page.emulateMedia({ reducedMotion });
    await page.goto("/present/?transition=slide");
    await expect(page.locator('input[type="file"]')).toBeEnabled();
    await page.locator('input[type="file"]').setInputFiles({
      name: "motion.md",
      mimeType: "text/plain",
      buffer: Buffer.from(
        '<!-- .slide: data-transition="zoom" data-background-transition="fade" -->\n' + deck,
      ),
    });
    await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
    const durations = await page
      .frameLocator("iframe")
      .locator(".slides, .slides section, .slide-background")
      .evaluateAll((elements) =>
        elements.map((element) => getComputedStyle(element).transitionDuration),
      );
    expect(durations.length).toBeGreaterThan(0);
    expect(
      durations.every((duration) => duration.split(",").every((value) => parseFloat(value) === 0)),
    ).toBe(true);
    await page.frameLocator("iframe").getByRole("heading", { name: "First", exact: true }).click();
    await page.keyboard.press("ArrowRight");
    await expect(
      page.frameLocator("iframe").getByRole("heading", { name: "Second", exact: true }),
    ).toBeVisible();
    await expect(page.locator("body")).toHaveAttribute("data-current-slide", "2");
  });
}
