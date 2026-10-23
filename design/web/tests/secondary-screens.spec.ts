import { expect, test } from "@playwright/test";

test("model search includes model IDs and can recover from no results", async ({ page }) => {
  await page.goto("/#/screens/model-picker");
  const phone = page.locator(".device-viewport");
  const search = phone.getByPlaceholder("Search models");
  await search.fill("claude-sonnet-4-5");
  await expect(phone.getByRole("button", { name: "Claude Sonnet 4.5" })).toBeVisible();
  await expect(phone.getByRole("button", { name: "Claude Opus 4.6" })).toHaveCount(0);
  await search.fill("missing-model");
  await expect(phone.getByRole("heading", { name: "No matching models" })).toBeVisible();
  await phone.getByRole("button", { name: "Clear search" }).click();
  await expect(search).toHaveValue("");
  await expect(phone.getByRole("button", { name: "Auto" })).toBeVisible();
});

test("knowledge loading fills the available screen without moving the header", async ({ page }) => {
  await page.goto("/#/screens/knowledge-list");
  await page.locator(".device-picker").getByRole("radio", { name: "loading", exact: true }).click();
  const phone = page.locator(".device-viewport");
  const status = phone.getByRole("status");
  await expect(status).toBeVisible();
  const heights = await phone.evaluate((el) => ({
    body: el.querySelector(".scroll")!.getBoundingClientRect().height,
    state: el.querySelector(".eigin-screen-state")!.getBoundingClientRect().height,
    overflow: el.scrollHeight - el.clientHeight,
  }));
  expect(heights.state / heights.body).toBeGreaterThan(0.75);
  expect(heights.overflow).toBeLessThanOrEqual(1);
});

test("sidebar scrolls when all app areas are expanded", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 650 });
  await page.goto("/#/screens/knowledge");
  const sidebar = page.locator(".sidebar");
  const collapsed = sidebar.locator("button[aria-expanded=false]");
  while (await collapsed.count()) {
    await collapsed.first().click();
  }
  await sidebar.evaluate((el) => el.scrollTo(0, el.scrollHeight));
  await expect.poll(() => sidebar.evaluate((el) => el.scrollTop)).toBeGreaterThan(0);
  await expect(sidebar.getByRole("button", { name: /Showcase/ })).toBeVisible();
});

for (const scenario of [
  { route: "knowledge-detail", action: "Delete knowledge", result: "Knowledge deleted" },
  { route: "intent-detail", action: "Dismiss intent", result: "Intent dismissed" },
  { route: "space-detail", action: "Delete space", result: "Space deleted" },
]) {
  test(`${scenario.action} requires modal confirmation`, async ({ page }) => {
    await page.goto(`/#/screens/${scenario.route}`);
    const phone = page.locator(".device-viewport");
    page.once("dialog", async (dialog) => {
      expect(dialog.type()).toBe("confirm");
      await dialog.dismiss();
    });
    await phone.getByRole("button", { name: scenario.action, exact: true }).click();
    await expect(phone.getByRole("button", { name: scenario.action, exact: true })).toBeVisible();
    await expect(phone.getByRole("heading", { name: scenario.result })).toHaveCount(0);
    page.once("dialog", async (dialog) => {
      expect(dialog.type()).toBe("confirm");
      await dialog.accept();
    });
    await phone.getByRole("button", { name: scenario.action, exact: true }).click();
    await expect(phone.getByRole("heading", { name: scenario.result })).toBeVisible();
  });
}

test("scenario controls stay above the device and clear on navigation", async ({ page }) => {
  await page.goto("/#/screens/model-picker");
  const controls = page.locator(".device-picker");
  await controls.getByRole("radio", { name: "empty", exact: true }).click();
  await expect(
    page.locator(".device-viewport").getByRole("heading", { name: "No models available" }),
  ).toBeVisible();
  await page.goto("/#/screens/about");
  await expect(controls.getByRole("radio", { name: "empty", exact: true })).toHaveCount(0);
});

test("knowledge list and graph have distinct gallery routes", async ({ page }) => {
  await page.goto("/#/screens/knowledge-list");
  await page.locator(".device-viewport").getByRole("radio", { name: "Graph", exact: true }).click();
  await expect(page).toHaveURL(/screens\/knowledge$/);
  await expect(page.locator(".graph-canvas")).toBeVisible();
  await page.locator(".device-viewport").getByRole("radio", { name: "List", exact: true }).click();
  await expect(page).toHaveURL(/screens\/knowledge-list$/);
});

test("feedback requires text and supports review and editing", async ({ page }) => {
  await page.goto("/#/screens/feedback");
  const dialog = page.getByRole("dialog");
  await expect(dialog.getByRole("button", { name: "Continue", exact: true })).toBeDisabled();
  await dialog
    .getByRole("textbox", { name: "Feedback message" })
    .fill("Please improve the knowledge graph.");
  await dialog.getByRole("button", { name: "Continue", exact: true }).click();
  await expect(dialog.getByText("Please improve the knowledge graph.")).toBeVisible();
  await dialog.getByRole("button", { name: "Edit report" }).click();
  await expect(dialog.getByRole("textbox", { name: "Feedback message" })).toHaveValue(
    "Please improve the knowledge graph.",
  );
});

test("logging reveals its dependent settings", async ({ page }) => {
  await page.goto("/#/screens/settings-advanced");
  const phone = page.locator(".device-viewport");
  await expect(phone.getByRole("button", { name: /Minimum level/ })).toHaveCount(0);
  await phone.getByRole("switch", { name: "Log to file" }).click();
  await expect(phone.getByRole("button", { name: /Minimum level/ })).toBeVisible();
});

test("secondary screens render in both themes without page errors", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  for (const route of [
    "model-picker",
    "knowledge",
    "knowledge-graph",
    "intents",
    "intent-detail",
    "skills",
    "skill-detail",
    "spaces",
    "space-detail",
    "permissions",
    "settings-advanced",
    "about",
    "feedback",
  ]) {
    await page.goto(`/#/screens/${route}`);
    await expect(page.locator(".device-viewport")).toBeVisible();
    for (const theme of ["Light", "Dark"]) {
      await page.locator(".sidebar").getByRole("radio", { name: theme, exact: true }).click();
      const overflow = await page
        .locator(".device-viewport")
        .evaluate((el) => el.scrollWidth - el.clientWidth);
      expect(overflow, `${route} in ${theme}`).toBeLessThanOrEqual(1);
    }
  }
  expect(errors).toEqual([]);
});

test("model selection uses the icon token in both themes", async ({ page }) => {
  await page.goto("/#/screens/model-picker");
  const phone = page.locator(".device-viewport");
  for (const theme of ["Light", "Dark"]) {
    await page.locator(".sidebar").getByRole("radio", { name: theme, exact: true }).click();
    for (const name of ["Auto", "Claude Sonnet 4.6"]) {
      await phone.getByRole("button", { name, exact: false }).first().click();
      const colors = await phone.locator(".selection-mark").evaluate((el) => {
        const probe = document.createElement("span");
        probe.style.color = "var(--color-icon-standard-base)";
        el.append(probe);
        const result = {
          actual: getComputedStyle(el).color,
          expected: getComputedStyle(probe).color,
        };
        probe.remove();
        return result;
      });
      expect(colors.actual).toBe(colors.expected);
    }
  }
});

test("loading has a larger indicator and no subtitle; empty state has an icon", async ({
  page,
}) => {
  await page.goto("/#/screens/model-picker");
  const phone = page.locator(".device-viewport");
  const controls = page.locator(".device-picker");
  await controls.getByRole("radio", { name: "loading", exact: true }).click();
  await expect(phone.getByRole("heading", { name: "Finding models" })).toBeVisible();
  await expect(phone.locator(".eigin-screen-state p")).toHaveCount(0);
  await expect(phone.locator(".eigin-screen-state svg")).toHaveAttribute("width", "48");
  await controls.getByRole("radio", { name: "empty", exact: true }).click();
  await expect(phone.locator(".eigin-screen-state .eigin-icon")).toBeVisible();
  await expect(phone.locator(".eigin-screen-state p")).not.toBeEmpty();
});

test("space identity, instructions editor, and privacy group match the design", async ({
  page,
}) => {
  await page.goto("/#/screens/space-detail");
  const phone = page.locator(".device-viewport");
  const emoji = phone.getByRole("button", { name: "Change symbol" });
  await expect(emoji).toHaveText("🚆");
  await phone.getByRole("button", { name: "Travel", exact: true }).click();
  await phone.getByLabel("Space name").fill("Trips");
  await phone.getByLabel("Space name").press("Enter");
  await expect(phone.getByRole("button", { name: "Trips", exact: true })).toBeVisible();
  await phone.getByRole("button", { name: "Instructions", exact: true }).click();
  const editor = phone.getByLabel("Space instructions");
  await expect(editor).toBeVisible();
  await expect(editor).toHaveValue(/Prefer trains over flights when practical\./);
  await editor.fill("Always prefer overnight trains.");
  await phone.getByRole("button", { name: "Back", exact: true }).click();
  await expect(phone.getByRole("button", { name: "Trips", exact: true })).toBeVisible();
  await expect(phone.getByText("Data created here stays hidden from other spaces.")).toBeVisible();
  const toggle = phone.getByRole("switch", { name: "Private space" });
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-checked", "true");
  await expect(phone.getByRole("button", { name: "Delete space", exact: true })).toBeVisible();
  await page.goto("/#/screens/spaces");
  await expect(phone.getByText("Your spaces")).toHaveCount(0);
  await page.locator(".device-picker").getByRole("radio", { name: "empty", exact: true }).click();
  await expect(phone.getByRole("heading", { name: "No spaces yet" })).toBeVisible();
});

test("knowledge previews show up to four items and open the complete category", async ({
  page,
}) => {
  await page.goto("/#/screens/knowledge-list");
  const phone = page.locator(".device-viewport");
  const things = phone
    .locator("section.group")
    .filter({ has: page.getByRole("heading", { name: "Things", exact: true }) });
  await expect(things.getByRole("button")).toHaveCount(5);
  await expect(things.getByRole("button", { name: "Show all things 27" })).toBeVisible();
  const facts = phone
    .locator("section.group")
    .filter({ has: page.getByRole("heading", { name: "Facts", exact: true }) });
  await expect(facts.getByRole("button")).toHaveCount(4);
  await expect(facts.getByRole("button", { name: /Show all/ })).toHaveCount(0);
  await things.getByRole("button", { name: "Show all things 27" }).click();
  await expect(phone.getByText("Things", { exact: true })).toBeVisible();
  await expect(phone.locator("section.group").getByRole("button")).toHaveCount(21);
  await phone.getByRole("button", { name: "Show 7 more", exact: true }).click();
  await expect(phone.locator("section.group").getByRole("button")).toHaveCount(27);
  await phone.getByRole("button", { name: "Learning Norwegian", exact: true }).click();
  await expect(phone.locator("section.group").first()).toContainText("Learning Norwegian");
  await phone.getByRole("button", { name: "Back", exact: true }).click();
  await expect(phone.getByText("Things", { exact: true })).toBeVisible();
  await phone.getByRole("button", { name: "Back", exact: true }).click();
  await expect(phone.getByRole("radio", { name: "List", exact: true })).toBeVisible();
});

test("knowledge ID is a field instead of a footer, including records without additional fields", async ({
  page,
}) => {
  await page.goto("/#/screens/knowledge-detail");
  const phone = page.locator(".device-viewport");
  const fields = phone
    .locator("section.group")
    .filter({ has: page.getByRole("heading", { name: "Fields", exact: true }) });
  await expect(
    fields.locator(".eigin-row").filter({ has: page.getByText("ID", { exact: true }) }),
  ).toContainText("train");
  await expect(phone.locator(".footnote")).toHaveCount(0);
  await phone.getByRole("button", { name: /^Oslo/ }).click();
  await phone.getByRole("button", { name: /^Learning Norwegian/ }).click();
  await expect(fields).toContainText("ID");
  await expect(fields).toContainText("norwegian");
  await expect(phone.locator(".footnote")).toHaveCount(0);
});

test("category batches retain earlier rows and scroll position after opening details", async ({
  page,
}) => {
  await page.goto("/#/screens/knowledge-list");
  const phone = page.locator(".device-viewport");
  await phone.getByRole("button", { name: "Show all things 27" }).click();
  const scroll = phone.locator(".category-page .scroll");
  await expect(phone.getByRole("button", { name: "Akureyri", exact: true })).toHaveCount(0);
  await phone.getByRole("button", { name: "Show 7 more", exact: true }).click();
  const last = phone.getByRole("button", { name: "Akureyri", exact: true });
  await last.scrollIntoViewIfNeeded();
  const position = await scroll.evaluate((element) => element.scrollTop);
  expect(position).toBeGreaterThan(100);
  await last.click();
  await expect(phone.getByText("saved_place_20", { exact: true })).toBeVisible();
  await phone.getByRole("button", { name: "Back", exact: true }).click();
  await expect(last).toBeVisible();
  await expect(phone.getByRole("button", { name: /Show .* more/ })).toHaveCount(0);
  await expect.poll(() => scroll.evaluate((element) => element.scrollTop)).toBeCloseTo(position, 0);
});

test("intent rows open their own content and return to the list", async ({ page }) => {
  await page.goto("/#/screens/intents");
  const phone = page.locator(".device-viewport");
  await phone.getByRole("button", { name: /^Make more time for cooking/ }).click();
  await expect(phone.locator("section.group").first()).toContainText("Make more time for cooking.");
  await expect(phone).toContainText("Plan this week’s meals");
  await expect(phone).not.toContainText("Compare train routes");
  await phone.getByRole("button", { name: "Back", exact: true }).click();
  await phone.getByRole("button", { name: /^Get the garden ready for spring/ }).click();
  await expect(phone).toContainText("Choose seeds");
  page.once("dialog", (dialog) => dialog.accept());
  await phone.getByRole("button", { name: "Dismiss intent", exact: true }).click();
  await expect(phone.getByRole("heading", { name: "Intent dismissed" })).toBeVisible();
});

test("secondary headers forward their trailing action", async ({ page }) => {
  await page.goto("/#/screens/spaces");
  await page
    .locator(".device-viewport")
    .getByRole("button", { name: "New space", exact: true })
    .click();
  await expect(page).toHaveURL(/#\/screens\/space-detail$/);
  await expect(
    page.locator(".device-viewport").getByRole("button", { name: "Change symbol" }),
  ).toBeVisible();
});
