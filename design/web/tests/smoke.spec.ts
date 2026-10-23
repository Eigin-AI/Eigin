import { expect, test } from "@playwright/test";

test("the sidebar folds its sections and opens the one you are in", async ({ page }) => {
  await page.goto("/#/components/rows");

  const sections = page.locator(".sidebar .header");

  // The section holding the current page opens itself; the others stay folded.
  await expect(sections.filter({ hasText: "Components" })).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator('.sidebar .header[aria-expanded="true"]')).toHaveCount(1);
  await expect(sections.filter({ hasText: "Agent" })).toHaveAttribute("aria-expanded", "false");
  // The header names the page you are on, so a folded section still tells you.
  await expect(page.locator(".sidebar").getByText("Content groups").first()).toBeVisible();

  // Match the header so an option in another group cannot select that group.
  const agentFold = page
    .locator(".sidebar .disclosure")
    .filter({ has: page.getByRole("button", { name: "Agent", exact: true }) })
    .locator(".reveal");
  expect(await agentFold.evaluate((el) => el.getBoundingClientRect().height)).toBe(0);

  await sections.filter({ hasText: "Agent" }).click();
  const agent = page.getByRole("radio", { name: "Agent", exact: true });
  await expect(agent).toBeVisible();
  await expect(sections.filter({ hasText: "Components" })).toHaveAttribute("aria-expanded", "true");
  await expect
    .poll(async () => agentFold.evaluate((el) => el.getBoundingClientRect().height))
    .toBeGreaterThan(20);

  await agent.click();
  await expect(page).toHaveURL(/#\/screens\/agent$/);
  await expect(agent).toHaveAttribute("aria-checked", "true");
});
