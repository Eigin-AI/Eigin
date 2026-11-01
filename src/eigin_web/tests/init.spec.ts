import { expect, test } from "@playwright/test";

test("initializes the real WASM SDK", async ({ page, browser }) => {
  console.log(`Testing ${browser.browserType().name()} ${browser.version()}`);
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Eigin SDK test host" }),
  ).toBeVisible();
  await expect(page.getByRole("status")).toHaveText("Eigin SDK initialized");
});

test("reports a WASM loading failure", async ({ page }) => {
  await page.route("**/*.wasm", (route) => route.abort());
  await page.goto("/");
  await expect(page.getByRole("status")).toContainText(
    "SDK initialization failed:",
  );
});
