import { expect, test } from "@playwright/test";

test("floating picker supports keyboard navigation and Escape", async ({ page, browserName }) => {
  await page.goto("/#/components/controls");
  const picker = page.locator(".floating-picker");
  const trigger = picker.locator(".picker-trigger");
  await trigger.focus();
  await page.keyboard.press("Enter");
  await expect(picker.getByRole("button", { name: "English", exact: true })).toBeVisible();
  await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
  await expect(picker.getByRole("button", { name: "English", exact: true })).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await expect(trigger).toBeFocused();
});

test("floating picker selects destinations and dismisses outside", async ({ page }) => {
  await page.goto("/#/components/controls");
  const picker = page.locator(".floating-picker");
  const trigger = picker.locator(".picker-trigger");
  await trigger.click();
  await picker.getByRole("button", { name: "Dansk", exact: true }).click();
  await expect(trigger).toHaveAccessibleName("Floating picker: Dansk");
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await trigger.click();
  await expect(picker.getByRole("button", { name: "Dansk", exact: true })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await page.getByRole("heading", { name: "Floating picker", exact: true }).click();
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await trigger.click();
  await page.getByRole("heading", { name: "Switch", exact: true }).evaluate((element) => {
    element.setAttribute("tabindex", "-1");
    element.focus();
  });
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
});

test("floating picker stays in the content area and follows scrolling", async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 700 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/#/components/controls");
  const picker = page.locator(".floating-picker");
  const trigger = picker.locator(".picker-trigger");
  const panel = picker.locator(".picker-panel");
  await trigger.click();
  await expect(panel).toBeVisible();
  await expect
    .poll(async () => {
      const popup = await panel.boundingBox();
      const content = await page.locator("main.content").boundingBox();
      return (
        !!popup &&
        !!content &&
        popup.x >= content.x &&
        popup.x + popup.width <= content.x + content.width
      );
    })
    .toBe(true);
  await page.locator("main.content").evaluate((element) => element.scrollBy(0, 20));
  await expect
    .poll(async () => {
      const popup = await panel.boundingBox();
      const trigger = await picker.locator(".picker-trigger").boundingBox();
      if (!popup || !trigger) return Infinity;
      const placement = await panel.getAttribute("data-placement");
      return placement?.startsWith("top")
        ? Math.abs(trigger.y - popup.y - popup.height - 8)
        : Math.abs(popup.y - trigger.y - trigger.height - 8);
    })
    .toBeLessThan(2);
});

test("floating picker opens above the trigger when the bottom has no room", async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 700 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/#/components/controls");
  await page
    .locator(".floating-picker")
    .locator("..")
    .evaluate((element) => {
      element.style.paddingTop = "440px";
    });
  const picker = page.locator(".floating-picker");
  await picker.locator(".picker-trigger").scrollIntoViewIfNeeded();
  await page.locator("main.content").evaluate((element) => {
    const trigger = element
      .querySelector(".floating-picker .picker-trigger")!
      .getBoundingClientRect();
    element.scrollBy(0, trigger.bottom - window.innerHeight + 20);
  });
  await picker.locator(".picker-trigger").click();
  await expect(picker.locator(".picker-panel")).toHaveAttribute("data-placement", /^top/);
  await expect
    .poll(async () => {
      const popup = await picker.locator(".picker-panel").boundingBox();
      const trigger = await picker.locator(".picker-trigger").boundingBox();
      return popup && trigger ? trigger.y - popup.y - popup.height : -Infinity;
    })
    .toBeGreaterThanOrEqual(7);
});

test("floating picker accepts detailed rows and contracts on ordinary close", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/#/components/controls");
  await page.getByRole("radio", { name: "Detailed rows", exact: true }).click();
  const picker = page.locator(".floating-picker");
  const trigger = picker.locator(".picker-trigger");
  await trigger.click();
  const reveal = picker.locator(".reveal");
  await expect(picker.getByRole("button", { name: /Personal.*Your own agent/ })).toBeVisible();
  await reveal.evaluate(async (element) => {
    await Promise.allSettled(element.getAnimations().map((animation) => animation.finished));
  });
  const height = (await reveal.boundingBox())!.height;
  await trigger.click();
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await expect
    .poll(
      async () => {
        const box = await reveal.boundingBox();
        return !!box && box.height > 0 && box.height < height;
      },
      { intervals: [16, 16, 16] },
    )
    .toBe(true);
  await expect(picker.locator(".picker-panel")).toHaveCount(0);
});

test("selecting a row dismisses immediately before changing its content", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/#/components/controls");
  const picker = page.locator(".floating-picker");
  await picker.locator(".picker-trigger").click();
  const option = picker.getByRole("button", { name: "Dansk", exact: true });
  await option.click();
  expect(await picker.locator(".picker-panel").count()).toBe(0);
  await expect(picker.locator(".picker-trigger")).toHaveAccessibleName("Floating picker: Dansk");
  await expect(picker.locator(".picker-trigger")).toBeFocused();
});

test("surface grows with row content within the shared width bounds", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/#/components/controls");
  await page.evaluate(() => document.fonts.ready);
  const picker = page.locator(".floating-picker");
  await picker.locator(".picker-trigger").click();
  const simpleWidth = (await picker.locator(".picker-panel").boundingBox())!.width;
  expect(simpleWidth).toBeCloseTo(180, 0);
  await picker.locator(".picker-trigger").click();
  await page.getByRole("radio", { name: "Detailed rows", exact: true }).click();
  await picker.locator(".picker-trigger").click();
  await expect
    .poll(async () => {
      const box = await picker.locator(".picker-panel").boundingBox();
      return !!box && box.width > simpleWidth && box.width <= 420;
    })
    .toBe(true);
  expect(
    await picker
      .locator(".panel-content")
      .evaluate((element) => element.scrollWidth <= element.clientWidth),
  ).toBe(true);
});
