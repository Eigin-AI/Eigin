import { expect, test } from "@playwright/test";

test("initializes concurrently and repeatedly without a UI framework", async ({
  page,
}) => {
  await page.goto("/tests/index.html");
  await page.waitForFunction(
    () => typeof (window as any).initializeSdk === "function",
  );
  await page.evaluate(async () => {
    const initialize = (window as any).initializeSdk;
    await Promise.all([initialize(), initialize()]);
    await initialize();
  });
});

test("registers diagnostics before initialization through the public wrapper", async ({
  page,
}) => {
  await page.goto("/tests/index.html");
  await page.waitForFunction(
    () => typeof (window as any).configureDiagnostics === "function",
  );
  await page.evaluate(() => (window as any).configureDiagnostics());
});

test("rejects when the runtime cannot load", async ({ page }) => {
  await page.route("**/*.wasm", (route) => route.abort());
  await page.goto("/tests/index.html");
  await page.waitForFunction(
    () => typeof (window as any).initializeSdk === "function",
  );
  const failed = await page.evaluate(async () => {
    try {
      await (window as any).initializeSdk();
      return false;
    } catch {
      return true;
    }
  });
  expect(failed).toBe(true);
});

test("delivers classified diagnostics and updates receiver policy", async ({
  page,
}) => {
  page.on("console", (message) => {
    if (message.text().startsWith("Browser bridge"))
      console.log(message.text());
  });
  await page.goto("/tests/errors.html");
  await page.waitForFunction(
    () => typeof (window as any).checkDiagnosticCallback === "function",
  );
  expect(
    await page.evaluate(() => (window as any).checkDiagnosticCallback()),
  ).toBe(true);
});

test("preserves the typed Rust error and its payload", async ({ page }) => {
  await page.goto("/tests/errors.html");
  await page.waitForFunction(
    () => typeof (window as any).checkTypedError === "function",
  );
  expect(await page.evaluate(() => (window as any).checkTypedError())).toBe(
    true,
  );
});
