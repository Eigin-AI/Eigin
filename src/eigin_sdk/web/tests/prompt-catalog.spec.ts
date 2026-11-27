import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/tests/prompt-catalog.html");
  await page.waitForFunction(() => typeof window.promptTests === "object");
});

test("bundled catalog renders through WASM", async ({ page }) => {
  await page.route("**/*.jinja", (route) => route.abort());
  expect(
    await page.evaluate(() => window.promptTests.bundled()),
  ).toBeGreaterThan(0);
});

test("hosts render independent catalogs and preflight usages", async ({
  page,
}) => {
  expect(await page.evaluate(() => window.promptTests.custom())).toEqual({
    withRole: "Hello Ada!\nRole: engineer",
    withoutRole: "Hello Lin!",
    withNote: "Hello Søren!\nRole: writer\nNote: Welcome 🌍",
    missing: true,
    preflight: true,
    independent: true,
  });
});
