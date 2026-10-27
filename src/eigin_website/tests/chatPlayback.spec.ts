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
        const ending = (await page.locator(".chat-ending").boundingBox())!;
        expect(ending.y + ending.height).toBeLessThanOrEqual(bounds.y + bounds.height);
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
  await expect(page.locator(".chat-ask")).toContainText("Should I take the new job?");
  await expect(page.locator(".chat-reply > span").first()).toContainText(
    "You wanted a chance to lead a team.",
  );
});
