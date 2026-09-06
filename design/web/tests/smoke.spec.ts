import { expect, test } from "@playwright/test";

test("the sidebar folds its sections and opens the one you are in", async ({ page }) => {
  await page.goto("/#/components/rows");

  const sections = page.locator(".sidebar .header");
  await expect(sections).toHaveCount(4);

  // The section holding the current page opens itself; the others stay folded.
  await expect(sections.filter({ hasText: "Components" })).toHaveAttribute("aria-expanded", "true");
  await expect(sections.filter({ hasText: "Main screens" })).toHaveAttribute(
    "aria-expanded",
    "false",
  );
  // The header names the page you are on, so a folded section still tells you.
  await expect(page.locator(".sidebar").getByText("Rows & groups").first()).toBeVisible();

  // Folded sections take no room, so the pages inside them are unreachable.
  const screensFold = page.locator(".sidebar .reveal").nth(2);
  expect(await screensFold.evaluate((el) => el.getBoundingClientRect().height)).toBe(0);

  await sections.filter({ hasText: "Main screens" }).click();
  await expect(page.getByRole("radio", { name: "Agent", exact: true })).toBeVisible();
  await expect
    .poll(async () => screensFold.evaluate((el) => el.getBoundingClientRect().height))
    .toBeGreaterThan(20);
});
