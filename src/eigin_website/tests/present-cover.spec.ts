import { expect, test } from "@playwright/test";

test("the recommended guide cover renders directly from the public example", async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto("/present/guide/");
  const markdown = await page.locator("#website-cover-example code").innerText();
  await page.goto("/present/render/?slide=1");
  const input = page.getByLabel("Choose a presentation file");
  await expect(input).toBeEnabled();
  await input.setInputFiles({
    name: "deck.md",
    mimeType: "text/plain",
    buffer: Buffer.from(markdown),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  const frame = page.frameLocator("iframe");
  await expect(frame.getByRole("heading", { name: "Eigin", exact: true })).toBeVisible();
  await expect(frame.locator(".website-event")).toHaveText("Your name · Role / Event");
  await expect(frame.locator(".website-cover > .slide-frame")).toHaveCSS(
    "background-color",
    "rgb(167, 176, 78)",
  );
  const logo = frame.locator(".website-logo");
  const wordmark = frame.locator(".website-wordmark");
  const logoBounds = (await logo.boundingBox())!;
  const wordmarkBounds = (await wordmark.boundingBox())!;
  expect(Math.abs(logoBounds.height - wordmarkBounds.height)).toBeLessThan(1);
  expect(Math.abs(logoBounds.y - wordmarkBounds.y)).toBeLessThan(1);
  await expect(logo).toHaveCSS("background-color", "rgb(30, 30, 29)");
  await frame.locator(".website-title").evaluate((el) => {
    (el as HTMLElement).style.color = "rgb(252, 230, 199)";
  });
  await expect(logo).toHaveCSS("background-color", "rgb(252, 230, 199)");
  await expect(wordmark).toHaveCSS("color", "rgb(252, 230, 199)");
  await frame.locator(".website-title").evaluate((el) => {
    (el as HTMLElement).style.removeProperty("color");
  });
  const bird = (await frame.locator(".website-bird").boundingBox())!;
  const title = (await frame.locator(".website-title").boundingBox())!;
  expect(bird.x).toBeGreaterThan(800);
  expect(bird.y).toBeLessThan(100);
  expect(title.x).toBe(70);
  expect(title.y).toBeGreaterThan(350);
  expect(title.x + title.width).toBeLessThanOrEqual(1210);
  await page.screenshot({
    path: testInfo.outputPath("presentation-title-example.png"),
    scale: "css",
  });
});
