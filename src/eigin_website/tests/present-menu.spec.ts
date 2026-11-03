import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/present/");
  await expect(page.locator('input[type="file"]')).toBeEnabled();
  await page.locator('input[type="file"]').setInputFiles({
    name: "menu.md",
    mimeType: "text/plain",
    buffer: Buffer.from("# Presentation menu\n\nNote:\nSpeaker notes\n\n---\n\n## Second slide"),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
});

test("floating slide menu supports shortcut, Escape, and slide-click dismissal", async ({
  page,
}, testInfo) => {
  const trigger = page.getByRole("button", { name: "Menu", exact: true });
  const actions = page.getByRole("navigation", { name: "Presentation actions" });
  await page.keyboard.press("m");
  await expect(trigger).toHaveAttribute("aria-expanded", "true");
  await expect(trigger).toBeFocused();
  await expect(actions).toBeVisible();
  const bounds = await actions.boundingBox();
  const viewport = page.viewportSize()!;
  expect(bounds!.x).toBeGreaterThanOrEqual(0);
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(viewport.width);
  await page.screenshot({ path: testInfo.outputPath("presentation-menu.png") });
  await page.keyboard.press("Escape");
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await expect(trigger).toBeFocused();
  await trigger.click();
  await expect(actions).toBeVisible();
  await page
    .frameLocator("iframe")
    .locator("body")
    .click({ position: { x: 20, y: viewport.height - 100 } });
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
});

test("picker actions dismiss before showing notes or slide overview", async ({ page }) => {
  const trigger = page.getByRole("button", { name: "Menu", exact: true });
  await trigger.click();
  await page.getByRole("button", { name: "Speaker notes", exact: true }).click();
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await expect(page.getByRole("complementary", { name: "Speaker notes" })).toBeVisible();
  await trigger.click();
  await expect(page.getByRole("button", { name: "Speaker notes", exact: true })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await page.getByRole("button", { name: "Slide overview", exact: true }).click();
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await expect(page.frameLocator("iframe").locator(".reveal")).toHaveClass(/overview/);
  await page.keyboard.press("Escape");
  await expect(page.frameLocator("iframe").locator(".reveal")).not.toHaveClass(/overview/);
});
