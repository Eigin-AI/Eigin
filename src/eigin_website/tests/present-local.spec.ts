import { expect, test } from "@playwright/test";

test("player ignores remote source parameters and hides legacy URL recents", async ({ page }) => {
  await page.clock.install();
  let remoteRequests = 0;
  await page.route(
    (url) => url.pathname === "/removed.md" || url.pathname === "/removed.zip",
    (route) => {
      remoteRequests++;
      return route.fulfill({ body: "# Remote deck" });
    },
  );
  await page.goto("/present/?src=/removed.md&zip=/removed.zip");
  await expect(page.locator('input[type="file"]')).toBeEnabled();
  await page.evaluate(async () => {
    await new Promise<void>((resolve, reject) => {
      const request = indexedDB.open("eigin-present", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("decks", { keyPath: "id" });
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const db = request.result;
        const tx = db.transaction("decks", "readwrite");
        tx.objectStore("decks").put({
          id: "src:/removed.md",
          kind: "src",
          src: "/removed.md",
          name: "Old hosted deck",
          lastOpened: Date.now(),
        });
        tx.oncomplete = () => {
          db.close();
          resolve();
        };
        tx.onerror = () => {
          db.close();
          reject(tx.error);
        };
      };
    });
  });
  await page.reload();
  await expect(page.locator('input[type="file"]')).toBeEnabled();
  await page.clock.runFor(2100);
  expect(remoteRequests).toBe(0);
  await expect(page.locator('input[type="url"]')).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Old hosted deck", exact: true })).toHaveCount(0);
  await expect(page.locator("iframe")).toHaveCount(0);
  await page.locator('input[type="file"]').setInputFiles({
    name: "local.md",
    mimeType: "text/plain",
    buffer: Buffer.from("# Local deck"),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "Local deck" }),
  ).toBeVisible();
});
