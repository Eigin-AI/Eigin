import { expect, test } from "@playwright/test";
import { zipSync, strToU8 } from "fflate";

test("readiness loads a local lazy image far beyond the selected slide", async ({ page }) => {
  const slides = Array.from({ length: 10 }, (_, i) => `# Slide ${i + 1}`);
  slides.push(
    '<h1>Distant slide</h1>\n<img data-src="media/later.svg" alt="Distant illustration">',
  );
  const buffer = Buffer.from(
    zipSync({
      "deck.md": strToU8(slides.join("\n\n---\n\n")),
      "media/later.svg": strToU8(
        '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="12"/></svg>',
      ),
    }),
  );
  await page.goto("/present/render/?slide=1");
  const input = page.getByLabel("Choose a presentation file");
  await expect(input).toBeEnabled();
  await input.setInputFiles({ name: "deck.zip", mimeType: "application/zip", buffer });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.locator("body")).toHaveAttribute("data-current-slide", "1");
  await expect(page.locator("body")).toHaveAttribute("data-total-slides", "11");
  expect(
    await page
      .frameLocator("iframe")
      .getByAltText("Distant illustration")
      .evaluate((el) => (el as HTMLImageElement).naturalWidth),
  ).toBe(32);
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("folder loading rejects oversized Markdown before rendering", async ({
  page,
  browserName,
}) => {
  test.skip(browserName !== "chromium", "Directory picker is Chromium-only.");
  await page.addInitScript(() => {
    Object.defineProperty(window, "showDirectoryPicker", {
      value: async () => {
        const root = await navigator.storage.getDirectory();
        const directory = await root.getDirectoryHandle("oversized", { create: true });
        const file = await directory.getFileHandle("deck.md", { create: true });
        const writer = await file.createWritable();
        await writer.truncate(64 * 1024 * 1024 + 1);
        await writer.close();
        return directory;
      },
    });
  });
  await page.goto("/present/");
  await page.getByRole("button", { name: "Open folder", exact: true }).click();
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "error");
  await expect(page.getByRole("alert")).toContainText("64 MiB input limit");
  await expect(page.locator("iframe")).toHaveCount(0);
});
