import { test, expect, type Locator } from "@playwright/test";

async function expectReadable(locator: Locator) {
  const contrast = await locator.evaluate((element) => {
    const channels = (color: string) => {
      const values = color.match(/[\d.]+/g)!.map(Number);
      return color.startsWith("color(srgb ")
        ? [...values.slice(0, 3).map((value) => value * 255), values[3] ?? 1]
        : values;
    };
    const over = (foreground: number[], background: number[]) => {
      const alpha = foreground[3] ?? 1;
      return background.map((channel, index) => foreground[index] * alpha + channel * (1 - alpha));
    };
    const backgrounds: number[][] = [];
    for (let node: Element | null = element; node; node = node.parentElement) {
      backgrounds.push(channels(getComputedStyle(node).backgroundColor));
    }
    let background = backgrounds
      .reverse()
      .reduce((result, layer) => over(layer, result), [255, 255, 255]);
    const overlay = getComputedStyle(element, "::before");
    if (overlay.content !== "none" && Number(overlay.opacity) > 0) {
      const color = channels(overlay.backgroundColor);
      color[3] = (color[3] ?? 1) * Number(overlay.opacity);
      background = over(color, background);
    }
    const foreground = over(channels(getComputedStyle(element).color), background);
    const luminance = (color: number[]) =>
      color
        .map((value) => {
          const channel = value / 255;
          return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
        })
        .reduce((result, value, index) => result + value * [0.2126, 0.7152, 0.0722][index], 0);
    const values = [luminance(foreground), luminance(background)];
    return (Math.max(...values) + 0.05) / (Math.min(...values) + 0.05);
  });
  expect(contrast, (await locator.textContent()) ?? "Text contrast").toBeGreaterThanOrEqual(4.5);
}

for (const path of [
  "/en/",
  "/en/roadmap/",
  "/en/trust/",
  "/en/privacy/",
  "/en/terms/",
  "/en/contact/",
  "/en/support/",
]) {
  for (const colorScheme of ["light", "dark"] as const) {
    test(`${path} copy and interactive links have readable contrast under ${colorScheme} preference`, async ({
      page,
      browserName,
    }) => {
      await page.emulateMedia({ colorScheme, reducedMotion: "reduce" });
      await page.goto(path);
      // The chat preview keeps the app's own placeholder colour, so it's left out.
      for (const copy of await page
        .locator(
          ".hero-bottom > p, .section-intro, .eyebrow, .muted:not(.chat-screen *), .document-prose p, .document-prose li, .reach-person .t-body, .feature-tabs button",
        )
        .all()) {
        if (await copy.isVisible()) await expectReadable(copy);
      }
      for (const link of await page.locator("a:not(.eigin-btn, .skip, .site-brand)").all()) {
        if (!(await link.isVisible())) continue;
        await expectReadable(link);
        await link.hover();
        await expectReadable(link);
        await page.mouse.move(0, 0);
        await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
        await link.focus();
        await expectReadable(link);
      }
      for (const button of await page.locator(".eigin-btn.spot").all()) {
        if (!(await button.isVisible())) continue;
        await expectReadable(button);
        await button.hover();
        await expect
          .poll(() => button.evaluate((element) => getComputedStyle(element, "::before").opacity))
          .toBe("1");
        await expectReadable(button);
        await page.mouse.down();
        await expectReadable(button);
        await page.mouse.move(0, 0);
        await page.mouse.up();
      }
    });
  }
}

for (const locale of ["en", "da"]) {
  test(`${locale} paused Trust diagrams retain readable labels`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(`/${locale}/trust/`);
    for (const diagram of await page.locator(".trust-claim-diagram").all()) {
      await diagram.scrollIntoViewIfNeeded();
      await expect(diagram).toHaveAttribute("data-active", "true");
      await diagram
        .getByRole("button", {
          name: locale === "en" ? "Pause illustration" : "Sæt illustration på pause",
        })
        .click();
      await expect(diagram).toHaveAttribute("data-active", "false");
      const figure = diagram.locator(".tschem");
      await expect(figure).toHaveCSS("filter", "none");
      await expect(figure).toHaveCSS("opacity", "1");
      for (const label of await diagram.locator(".ts-name, .ts-label").all()) {
        await expectReadable(label);
      }
    }
  });
}
