import { expect, test } from "@playwright/test";

test("initializes concurrently and repeatedly without a UI framework", async ({
  page,
}) => {
  await page.goto("/tests/index.html");
  await page.waitForFunction(() => typeof window.initializeSdk === "function");
  await page.evaluate(async () => {
    const initialize = window.initializeSdk;
    await Promise.all([initialize(), initialize()]);
    await initialize();
  });
});

test("registers diagnostics before initialization through the public wrapper", async ({
  page,
}) => {
  await page.goto("/tests/index.html");
  await page.waitForFunction(
    () => typeof window.configureDiagnostics === "function",
  );
  await page.evaluate(() => window.configureDiagnostics());
});

test("rejects when the runtime cannot load", async ({ page }) => {
  await page.route("**/*.wasm", (route) => route.abort());
  await page.goto("/tests/index.html");
  await page.waitForFunction(() => typeof window.initializeSdk === "function");
  const failed = await page.evaluate(async () => {
    try {
      await window.initializeSdk();
      return false;
    } catch {
      return true;
    }
  });
  expect(failed).toBe(true);
});

test("round-trips Unicode context values through WASM", async ({ page }) => {
  await page.goto("/tests/context.html");
  await page.waitForFunction(() => typeof window.checkContext === "function");
  expect(await page.evaluate(() => window.checkContext())).toBe(true);
});
