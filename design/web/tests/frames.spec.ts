import { expect, test } from "@playwright/test";

/* Frames behaviour, as rendered in the gallery. */

test("the bezel is the same thickness on every side", async ({ page }) => {
  await page.goto("/#/screens/agent");

  const bezel = await page.evaluate(() => {
    const frame = document.querySelector(".device-frame")!.getBoundingClientRect();
    const screen = document.querySelector(".device-screen")!.getBoundingClientRect();
    return {
      left: screen.left - frame.left,
      right: frame.right - screen.right,
      top: screen.top - frame.top,
      bottom: frame.bottom - screen.bottom,
    };
  });

  // Scaling to fit shrinks all four together, so compare them to each other.
  expect(bezel.right).toBeCloseTo(bezel.left, 1);
  expect(bezel.top).toBeCloseTo(bezel.left, 1);
  expect(bezel.bottom).toBeCloseTo(bezel.left, 1);
});

test("the status bar owns the top safe area and the header clears it", async ({ page }) => {
  await page.goto("/#/screens/chat-list");

  const geometry = await page.evaluate(() => {
    const screen = document.querySelector(".device-screen")!.getBoundingClientRect();
    const bar = document.querySelector(".status-bar")!.getBoundingClientRect();
    const header = document.querySelector(".nav-header .frame")!.getBoundingClientRect();
    return {
      barTop: Math.round(bar.top - screen.top),
      barHeight: Math.round(bar.height),
      headerContentTop: Math.round(header.top - screen.top),
    };
  });

  // The bar fills the declared inset, and the header's content starts below it.
  expect(geometry.barTop).toBe(0);
  expect(geometry.barHeight).toBe(59);
  expect(geometry.headerContentTop).toBeGreaterThanOrEqual(59);
});

test("a configuration reshapes the frame and its chrome", async ({ page }) => {
  await page.goto("/#/screens/settings");

  const screen = page.locator(".device-screen");
  const declared = () =>
    screen.evaluate((el) => {
      const style = getComputedStyle(el);
      return { width: style.width, height: style.height };
    });

  expect(await declared()).toEqual({ width: "393px", height: "852px" });
  await expect(page.locator(".status-bar")).toBeVisible();

  await page.getByRole("radio", { name: "Landscape" }).click();

  await expect.poll(declared).toEqual({ width: "852px", height: "393px" });
  // Landscape reserves no top inset, so the status bar has no room to live in.
  await expect(page.locator(".status-bar")).toHaveCount(0);
  await expect(page.locator(".home-indicator")).toHaveCount(1);
});

test("a frame too wide for the stage is scaled, not clipped", async ({ page }) => {
  await page.setViewportSize({ width: 1000, height: 800 });
  await page.goto("/#/screens/settings");

  await page.getByRole("radio", { name: "Landscape" }).click();

  // Both bezels stay in view: the frame shrinks rather than running off.
  await expect
    .poll(async () =>
      page.evaluate(() => {
        const fit = document.querySelector(".device-fit")!.getBoundingClientRect();
        const stage = document.querySelector(".stage")!.getBoundingClientRect();
        return Math.round(stage.right - fit.right);
      }),
    )
    .toBe(24);

  const leftGap = await page.evaluate(() => {
    const fit = document.querySelector(".device-fit")!.getBoundingClientRect();
    const stage = document.querySelector(".stage")!.getBoundingClientRect();
    return Math.round(fit.left - stage.left);
  });
  expect(leftGap).toBe(24);
});

test("the island turns with the phone", async ({ page }) => {
  await page.goto("/#/screens/chat-list");

  const island = page.locator(".island");
  const shape = async () => {
    const box = (await island.boundingBox())!;
    return box.width > box.height ? "wide" : "tall";
  };

  // Hardware, so it is there in both configurations — lying down, then upright.
  expect(await shape()).toBe("wide");

  await page.getByRole("radio", { name: "Landscape" }).click();
  await expect.poll(shape).toBe("tall");
});
