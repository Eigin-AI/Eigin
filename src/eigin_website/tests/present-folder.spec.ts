import { expect, test } from "@playwright/test";

test("folder loading, live editing, and persisted recents use real browser handles", async ({
  page,
  browserName,
}, testInfo) => {
  test.skip(browserName !== "chromium", "Directory picker is Chromium-only.");
  await page.addInitScript(() => {
    Object.defineProperty(window, "showDirectoryPicker", {
      value: async () => {
        const root = await navigator.storage.getDirectory();
        const directory = await root.getDirectoryHandle("presentation", { create: true });
        const handle = await directory.getFileHandle("deck.md", { create: true });
        const writer = await handle.createWritable();
        await writer.write("# Original folder deck");
        await writer.close();
        return directory;
      },
    });
  });
  await page.goto("/present/");
  await page.getByRole("button", { name: "Open folder", exact: true }).click();
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  expect(new URL(page.url()).searchParams.get("deck")).toMatch(/^dir:/);
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const directory = await root.getDirectoryHandle("presentation");
    const handle = await directory.getFileHandle("deck.md");
    const writer = await handle.createWritable();
    await writer.write("# Edited folder deck");
    await writer.close();
  });
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "Edited folder deck" }),
  ).toBeVisible();
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const directory = await root.getDirectoryHandle("presentation");
    const writer = await (await directory.getFileHandle("deck.md")).createWritable();
    await writer.write("# Edited folder deck\n\n![Added asset](new.svg)");
    await writer.close();
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "error");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const directory = await root.getDirectoryHandle("presentation");
    const writer = await (
      await directory.getFileHandle("new.svg", { create: true })
    ).createWritable();
    await writer.write(
      '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="12"/></svg>',
    );
    await writer.close();
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.frameLocator("iframe").getByRole("img", { name: "Added asset" })).toBeVisible();
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const directory = await root.getDirectoryHandle("presentation");
    const writer = await (await directory.getFileHandle("new.svg")).createWritable();
    await writer.write(
      '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="32"><circle cx="16" cy="16" r="12"/></svg>',
    );
    await writer.close();
  });
  await expect
    .poll(() =>
      page
        .frameLocator("iframe")
        .getByRole("img", { name: "Added asset" })
        .evaluate((el) => (el as HTMLImageElement).naturalWidth),
    )
    .toBe(64);
  await page.reload();
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "Edited folder deck" }),
  ).toBeVisible();
  await page.goto("/present/");
  const recents = page.getByRole("table", { name: "Recent decks" });
  const row = recents
    .getByRole("row")
    .filter({ has: page.getByRole("rowheader", { name: "presentation", exact: true }) });
  await expect(row).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath("recent-decks.png"), fullPage: true });
  await row.getByRole("button", { name: "Open", exact: true }).click();
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "Edited folder deck" }),
  ).toBeVisible();
  await page.goto("/present/");
  await row.getByRole("button", { name: "Forget presentation", exact: true }).click();
  await expect(recents).toHaveCount(0);
  expect(
    await page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const directory = await root.getDirectoryHandle("presentation");
      return (await (await directory.getFileHandle("deck.md")).getFile()).text();
    }),
  ).toContain("Edited folder deck");
});
