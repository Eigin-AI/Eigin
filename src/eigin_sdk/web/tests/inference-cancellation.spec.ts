import { test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  test.setTimeout(15_000);
  await page.goto("/tests/inference-cancellation.html");
  await page.waitForFunction(() => window.providerTests !== undefined);
});

test("return interrupts pending headers and body without an AbortSignal", async ({
  page,
}) => {
  await page.evaluate(() => window.providerTests.returnInterruptsPendingRead());
});

test("host cancellation reaches Fetch for discovery and validation", async ({
  page,
}) => {
  await page.evaluate(() => window.providerTests.discoveryCancellation());
});
