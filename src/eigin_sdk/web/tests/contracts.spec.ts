import { test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  test.setTimeout(15_000);
  await page.goto("/tests/contracts.html");
  await page.waitForFunction(() => window.contracts !== undefined);
});

test("initialization error preserves reason", async ({ page }) => {
  await page.evaluate(() =>
    window.contracts.initializationErrorPreservesReason(),
  );
});

test("pending success preserves value", async ({ page }) => {
  await page.evaluate(() => window.contracts.pendingSuccessPreservesValue());
});

test("pending failure preserves variant and payload", async ({ page }) => {
  await page.evaluate(() =>
    window.contracts.pendingFailurePreservesVariantAndPayload(),
  );
});

test("operations complete independently", async ({ page }) => {
  await page.evaluate(() => window.contracts.operationsCompleteIndependently());
});

test("diagnostic callbacks preserve context and privacy policy", async ({
  page,
}) => {
  await page.evaluate(() =>
    window.contracts.diagnostics.privacyAndContextSurviveCallbacks(),
  );
});

test("diagnostic delivery follows filtering, replacement, and clear", async ({
  page,
}) => {
  await page.evaluate(() =>
    window.contracts.diagnostics.filteringReplacementAndClearControlDelivery(),
  );
});
