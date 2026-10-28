import { expect, test } from "@playwright/test";

for (const locale of ["en", "da"]) {
  test(`${locale} demo examples fit the stage and remain readable with reduced motion`, async ({
    page,
  }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(`/${locale}/`);
    await page.evaluate(() => document.fonts.ready);
    const choices = page.locator(".feature-tabs button");
    const screen = page.locator(".chat-screen");
    await expect(screen).toHaveAttribute("data-ready", "true");
    await expect(choices).toHaveCount(4);
    await expect(page.locator(".chat-ending .visual")).toHaveCount(0);
    await expect(page.locator(".chat-action-arrow")).toHaveCount(1);
    for (const width of [320, 360, 375, 390, 768, 851, 1024, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      for (let i = 0; i < 4; i++) {
        await choices.nth(i).click();
        await expect(choices.nth(i)).toHaveAttribute("aria-pressed", "true");
        await expect(screen).toHaveAttribute("data-phase", "reply");
        const prompt = page.locator(".chat-compose .collapsed > span");
        await expect(prompt).toHaveText(await page.locator(".chat-ask .body").innerText());
        expect(
          await prompt.evaluate((element) => element.scrollWidth <= element.clientWidth + 1),
        ).toBe(true);
        expect(
          await prompt.evaluate(
            (element) =>
              element.getBoundingClientRect().height <=
              element.parentElement!.getBoundingClientRect().height + 1,
          ),
        ).toBe(true);
        const bounds = (await screen.boundingBox())!;
        const turn = (await page.locator(".chat-turn").boundingBox())!;
        const agent = (await page.locator(".chat-agent").boundingBox())!;
        const blob = (await page.locator(".chat-agent .morph-blob path").boundingBox())!;
        const tool = (await page.locator(".chat-tool").boundingBox())!;
        expect(Math.abs(agent.x + agent.width / 2 - turn.x - 20)).toBeLessThan(1);
        expect(tool.x - blob.x - blob.width).toBeGreaterThanOrEqual(8);
        const ending = (await page.locator(".chat-ending").boundingBox())!;
        expect(ending.y + ending.height).toBeLessThanOrEqual(bounds.y + bounds.height);
        if (i === 2) {
          await expect(page.locator(".chat-tool")).toHaveText(
            locale === "en" ? "Checking Aula" : "Tjekker Aula",
          );
          await expect(page.locator(".chat-reply")).toContainText(
            locale === "en" ? "outdoor day at kindergarten" : "udedag i børnehaven",
          );
        }
        const reply = page.locator(".chat-reply");
        await expect(reply).not.toBeEmpty();
        await expect(page.locator(".chat-stage .sr-only")).toContainText(await reply.innerText());
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
          true,
        );
      }
    }
    await expect(page.locator(".chat-controls button")).toHaveCount(0);
  });
}

test("demo stages the question and answer, pauses, and leaves approval to the user", async ({
  page,
}) => {
  test.setTimeout(45000);
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  const screen = page.locator(".chat-screen");
  await expect(screen).toHaveAttribute("data-phase", "intro");
  await screen.scrollIntoViewIfNeeded();
  await expect(screen).toHaveAttribute("data-phase", "compose", { timeout: 5000 });
  await expect(page.locator(".chat-compose")).toHaveCSS("visibility", "visible");
  await expect(screen).toHaveCSS("--question", "0");
  await page.getByRole("button", { name: "Pause demo", exact: true }).click();
  const draft = await page.locator(".chat-compose .collapsed").innerText();
  await page.waitForTimeout(1200);
  expect(await page.locator(".chat-compose .collapsed").innerText()).toBe(draft);
  await page.getByRole("button", { name: "Play demo", exact: true }).click();
  await expect(screen).toHaveAttribute("data-phase", "thinking", { timeout: 7000 });
  await expect(screen).toHaveAttribute("data-phase", "reply", { timeout: 5000 });
  await expect(screen).toHaveCSS("--ending", "1");
  await expect(page.locator(".chat-tool")).toHaveCSS("opacity", "1");
  const tool = (await page.locator(".chat-tool").boundingBox())!;
  const agent = (await page.locator(".chat-agent").boundingBox())!;
  expect(Math.abs(tool.y + tool.height / 2 - agent.y - agent.height / 2)).toBeLessThan(1);
  const blob = (await page.locator(".chat-agent .morph-blob path").boundingBox())!;
  expect(tool.x - blob.x - blob.width).toBeGreaterThanOrEqual(4);
  await expect(page.locator(".chat-ending .surface")).toContainText("Add to calendar");
  await page.getByRole("button", { name: "Pause demo", exact: true }).click();
  await page.waitForTimeout(1200);
  await expect(page.locator(".chat-ending .surface")).toContainText("Add to calendar");
  await expect(screen).toHaveAttribute("inert", "");
  await page.getByRole("button", { name: "Play demo", exact: true }).click();
  await expect(page.locator(".feature-tabs button").nth(1)).toHaveAttribute(
    "aria-pressed",
    "true",
    { timeout: 14000 },
  );
});

test("demo has a complete example without JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto("/en/");
  await expect(page.locator(".chat-screen")).toHaveAttribute("data-phase", "reply");
  await expect(page.locator(".chat-stage .sr-only")).toContainText("Your first meeting is at 10.");
  await expect(page.locator(".chat-controls button")).toHaveCount(0);
  await context.close();
});

test("the opening blob is centered and moves before content is revealed", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  const screen = page.locator(".chat-screen");
  await screen.scrollIntoViewIfNeeded();
  await page.getByRole("button", { name: "Pause demo", exact: true }).click();
  await expect(screen).toHaveAttribute("data-phase", "intro");
  const stage = (await screen.boundingBox())!;
  const blob = (await page.locator(".chat-agent").boundingBox())!;
  expect(Math.abs(blob.x + blob.width / 2 - stage.x - stage.width / 2)).toBeLessThan(1);
  expect(Math.abs(blob.y + blob.height / 2 - stage.y - stage.height / 2)).toBeLessThan(1);
  await expect(page.locator(".chat-agent .agent-mark")).toHaveCount(0);
  await page.getByRole("button", { name: "Play demo", exact: true }).click();
  await expect(screen).toHaveAttribute("data-phase", "rising", { timeout: 5000 });
  await expect(page.locator(".chat-compose")).toHaveCSS("visibility", "hidden");
  await expect(screen).toHaveCSS("--question", "0");
  await expect(screen).toHaveAttribute("data-phase", "moving", { timeout: 10000 });
  await expect(page.locator(".chat-compose")).toHaveCSS("visibility", "hidden");
  await expect(screen).toHaveCSS("--question", "0");
  await expect(screen).toHaveAttribute("data-phase", "thinking", { timeout: 3000 });
  await expect(screen).toHaveCSS("--question", "1");
  const ask = (await page.locator(".chat-ask").boundingBox())!;
  const settledBlob = (await page.locator(".chat-agent").boundingBox())!;
  expect(settledBlob.y).toBeGreaterThan(ask.y + ask.height);
});

test("choosing an example while paused shows its complete exchange", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  await page.locator(".chat-screen").scrollIntoViewIfNeeded();
  await page.getByRole("button", { name: "Pause demo", exact: true }).click();
  await page.getByRole("button", { name: "Think through a hard decision", exact: true }).click();
  await expect(page.getByRole("button", { name: "Play demo", exact: true })).toBeVisible();
  await expect(page.locator(".chat-screen")).toHaveAttribute("data-phase", "reply");
  await expect(page.locator(".chat-screen")).toHaveCSS("--answer", "1");
  await expect(page.locator(".chat-ask")).toContainText("Which job offer fits my priorities?");
  await expect(page.locator(".chat-reply > span").first()).toContainText(
    "You wanted a chance to lead a team.",
  );
});

test("switching cases clears the current content and returns the blob before showing the latest choice", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  const screen = page.locator(".chat-screen");
  const choices = page.locator(".feature-tabs button");
  await screen.scrollIntoViewIfNeeded();
  await expect(screen).toHaveAttribute("data-phase", "compose", { timeout: 5000 });
  await choices.nth(1).click();
  await expect(screen).toHaveAttribute("data-phase", "switching");
  await expect(page.locator(".chat-ask")).toContainText("Make time for my presentation today");
  await choices.nth(3).click();
  await expect(screen).toHaveAttribute("data-phase", "intro", { timeout: 2000 });
  await page.getByRole("button", { name: "Pause demo", exact: true }).click();
  await expect(page.locator(".chat-ask")).toContainText("Which emails need a reply today?");
  const bounds = (await screen.boundingBox())!;
  const blob = (await page.locator(".chat-agent").boundingBox())!;
  expect(Math.abs(blob.x + blob.width / 2 - bounds.x - bounds.width / 2)).toBeLessThan(1);
  expect(Math.abs(blob.y + blob.height / 2 - bounds.y - bounds.height / 2)).toBeLessThan(1);
});

test("case labels crossfade selection and respond to hover and keyboard focus", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  await expect(page.locator(".chat-screen")).toHaveAttribute("data-ready", "true");
  const choices = page.locator(".feature-tabs button");
  const choice = choices.nth(1);
  await choice.scrollIntoViewIfNeeded();
  const arrowColor = await choice
    .locator(".feature-bullet-icon")
    .evaluate((element) => getComputedStyle(element).color);
  const initial = await choice.evaluate((element) => getComputedStyle(element).color);
  await choice.hover();
  await expect
    .poll(() => choice.evaluate((element) => getComputedStyle(element).color))
    .not.toBe(initial);
  await page.mouse.move(0, 0);
  await choice.focus();
  await expect
    .poll(() => choice.evaluate((element) => getComputedStyle(element).color))
    .not.toBe(initial);
  await choice.press("Enter");
  await expect(choice.locator("strong")).toHaveCSS("opacity", "1");
  await expect(choices.first().locator("strong")).toHaveCSS("opacity", "0");
  await expect(choice.locator(".feature-bullet-icon")).toHaveCSS("color", arrowColor);
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect(choice.locator("strong")).toHaveCSS("transition-duration", "0s");
});

test("selecting an off-screen example updates its accessible transcript immediately", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 200 });
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  const screen = page.locator(".chat-screen");
  await expect(screen).toHaveAttribute("data-ready", "true");
  const choice = page.locator(".feature-tabs button").nth(1);
  await choice.evaluate((element) =>
    element.scrollIntoView({ block: "start", behavior: "instant" }),
  );
  await expect(screen).not.toBeInViewport();
  await choice.click();
  await expect(choice).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator(".chat-stage .sr-only")).toContainText(
    "Which job offer fits my priorities?",
  );
  await expect(screen).not.toHaveAttribute("data-phase", "switching");
});

test("returning to the displayed example cancels a pending switch", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  const screen = page.locator(".chat-screen");
  const choices = page.locator(".feature-tabs button");
  await screen.scrollIntoViewIfNeeded();
  await expect(screen).toHaveAttribute("data-phase", "compose", { timeout: 5000 });
  await choices.nth(1).click();
  await expect(screen).toHaveAttribute("data-phase", "switching");
  await choices.first().click();
  await expect(screen).not.toHaveAttribute("data-phase", "switching");
  await page.waitForTimeout(650);
  await expect(screen).not.toHaveAttribute("data-phase", "intro");
  await expect(page.locator(".chat-stage .sr-only")).toContainText(
    "Make time for my presentation today",
  );
  await expect(choices.first()).toHaveAttribute("aria-pressed", "true");
});
