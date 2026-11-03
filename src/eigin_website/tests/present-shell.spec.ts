import { expect, test } from "@playwright/test";

test("launcher and guide fit the viewport and keep navigation usable", async ({
  page,
  isMobile,
}, testInfo) => {
  await page.goto("/present/");
  await expect(page.getByRole("heading", { name: "Ready to present." })).toBeVisible();
  await expect(page.getByRole("button", { name: "Load ZIP or Markdown" })).toBeEnabled();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath("presentation-launcher.png"), fullPage: true });
  await page.getByRole("link", { name: "Authoring guide", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Deck authoring guide", exact: true }),
  ).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath("presentation-guide.png") });
  if (isMobile) await page.locator(".document-mobile-index summary").click();
  await page.getByRole("link", { name: "3. Previewing a slide", exact: true }).click();
  await expect(page).toHaveURL(/#preview$/);
  await expect(
    page.getByRole("heading", { name: "3. Previewing a slide", exact: true }),
  ).toBeInViewport();
});

test("speaker notes have a readable scrollable surface and dismiss cleanly", async ({
  page,
}, testInfo) => {
  await page.goto("/present/");
  const input = page.getByLabel("Choose a presentation file");
  await expect(input).toBeEnabled();
  await input.setInputFiles({
    name: "notes.md",
    mimeType: "text/plain",
    buffer: Buffer.from(
      "# A clearer conversation\n\nNote:\nStart with the question: what would make this useful?\n\nGive the audience a moment to think.\n\n" +
        "Keep the next step concrete.\n".repeat(30),
    ),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  await page.getByRole("button", { name: "Speaker notes", exact: true }).click();
  const notes = page.getByRole("complementary", { name: "Speaker notes" });
  await expect(notes).toBeVisible();
  await expect(notes.getByRole("heading", { name: "Speaker notes" })).toBeVisible();
  expect(
    await notes
      .locator(".presentation-notes-copy")
      .evaluate((el) => el.scrollHeight > el.clientHeight),
  ).toBe(true);
  const bounds = (await notes.boundingBox())!;
  const viewport = page.viewportSize()!;
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(viewport.height);
  await page.screenshot({ path: testInfo.outputPath("speaker-notes.png") });
  await notes.getByRole("button", { name: "Close notes" }).click();
  await expect(notes).toHaveCount(0);
});
