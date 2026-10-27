import { expect, test } from "@playwright/test";

const viewports = [
  ...[375, 600, 601, 640, 641, 768, 1024, 1280, 1440, 1919, 1920, 2246, 2560, 3840].map(
    (width) => ({
      width,
      height: 900,
    }),
  ),
  { width: 1440, height: 500 },
  { width: 2246, height: 600 },
];

for (const locale of ["en", "da"]) {
  test(`${locale} hero birds keep clear of the text and viewport`, async ({ page }) => {
    test.setTimeout(60_000);
    await page.emulateMedia({ reducedMotion: "reduce" });
    let relativeTextClearance: number | undefined;
    for (const viewport of viewports) {
      await page.setViewportSize(viewport);
      await page.goto(`/${locale}/`);
      await page.evaluate(() => document.fonts.ready);
      const hero = page.locator(".hero");
      const flight = hero.locator(".hero-bird-flight");
      const edge = hero.locator(".hero-bird-edge");
      await expect(hero.getByRole("heading", { level: 1 })).toBeVisible();
      await expect(hero.getByRole("link")).toBeVisible();
      await expect(hero.getByRole("img")).toHaveCount(0);
      for (const bird of [flight, edge]) {
        await expect(bird).toHaveAttribute("aria-hidden", "true");
      }
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
        `${viewport.width}px should not overflow horizontally`,
      ).toBe(true);

      if (viewport.width <= 640) {
        await expect(flight).toBeHidden();
      } else {
        await expect(flight).toBeVisible();
        const metrics = await hero.evaluate((element) => {
          const heading = element.querySelector("h1")!;
          const text = heading.querySelector(".hero-first-line")!.firstChild!;
          const firstLine = document.createRange();
          firstLine.selectNodeContents(text);
          const bird = element.querySelector(".hero-bird-flight")!.getBoundingClientRect();
          return {
            topClearance: bird.top - element.getBoundingClientRect().top,
            rightClearance: innerWidth - bird.right,
            textClearance: bird.left - firstLine.getBoundingClientRect().right,
            secondLineClearance:
              heading.getBoundingClientRect().top +
              parseFloat(getComputedStyle(heading).lineHeight) -
              bird.bottom,
            aspectRatio: bird.width / bird.height,
            fontSize: parseFloat(getComputedStyle(heading).fontSize),
          };
        });
        expect(metrics.topClearance).toBeGreaterThanOrEqual(24);
        expect(metrics.rightClearance).toBeGreaterThanOrEqual(23.5);
        expect(metrics.textClearance).toBeGreaterThanOrEqual(0);
        const relativeClearance = metrics.textClearance / metrics.fontSize;
        relativeTextClearance ??= relativeClearance;
        expect(relativeClearance).toBeCloseTo(relativeTextClearance, 2);
        if (viewport.width >= 768) {
          expect(metrics.rightClearance).toBeGreaterThanOrEqual(64);
        }
        expect(metrics.secondLineClearance).toBeGreaterThanOrEqual(8);
        expect(metrics.aspectRatio).toBeCloseTo(816 / 764, 2);
      }

      if (viewport.width < 1920) {
        await expect(edge).toBeHidden();
      } else {
        await expect(edge).toBeVisible();
        const bird = (await edge.boundingBox())!;
        const heading = (await hero.locator("h1").boundingBox())!;
        expect(bird.x).toBeLessThan(0);
        expect(bird.x + bird.width).toBeGreaterThanOrEqual(240);
        expect(heading.x - (bird.x + bird.width)).toBeGreaterThanOrEqual(64);
      }
    }
  });
}

test("hero artwork renders without JavaScript", async ({ browser, baseURL }) => {
  const context = await browser.newContext({
    baseURL,
    javaScriptEnabled: false,
    viewport: { width: 2246, height: 994 },
  });
  try {
    const page = await context.newPage();
    await page.goto("/en/");
    await expect(page.locator(".hero-bird-flight svg")).toBeVisible();
    await expect(page.locator(".hero-bird-edge svg")).toBeVisible();
    await page.locator(".hero-cta a").click();
    await expect(page).toHaveURL(/#get$/);
  } finally {
    await context.close();
  }
});

test("left bird quickly slides and fades at the wide breakpoint", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.setViewportSize({ width: 1919, height: 994 });
  await page.goto("/en/");
  await page.evaluate(() => document.fonts.ready);
  const edge = page.locator(".hero-bird-edge");
  await expect(edge).toBeHidden();
  await expect(edge).toHaveCSS("transition-duration", "0.15s, 0.15s, 0s");
  // Slow playback so intermediate frames can be sampled deterministically.
  await page.addStyleTag({ content: ".hero-bird-edge { --motion-fast: 1000ms; }" });

  for (const width of [1920, 1919]) {
    await page.setViewportSize({ width, height: 994 });
    const middle = await edge.evaluate((node) => {
      getComputedStyle(node).opacity;
      const animations = node.getAnimations();
      const duration = Math.max(
        ...animations.map((animation) => Number(animation.effect!.getTiming().duration)),
      );
      for (const animation of animations) {
        animation.pause();
        animation.currentTime = duration / 2;
      }
      const style = getComputedStyle(node);
      return {
        opacity: Number(style.opacity),
        visibility: style.visibility,
        animatedProperties: animations.map(
          (animation) => (animation as CSSTransition).transitionProperty,
        ),
      };
    });
    expect(middle.animatedProperties).toContain("opacity");
    expect(middle.animatedProperties).toContain("transform");
    expect(middle.opacity).toBeGreaterThan(0);
    expect(middle.opacity).toBeLessThan(1);
    expect(middle.visibility).toBe("visible");
    const heading = await page.locator("h1").boundingBox();
    await edge.evaluate((node) => node.getAnimations().forEach((animation) => animation.finish()));
    await expect(edge).toHaveCSS("opacity", width === 1920 ? "1" : "0");
    if (width === 1920) await expect(edge).toBeVisible();
    else await expect(edge).toBeHidden();
    expect(await page.locator("h1").boundingBox()).toEqual(heading);
    expect(
      await page.locator(".hero-bird-flight").evaluate((node) => node.getAnimations().length),
    ).toBe(0);
  }
});

test("left bird changes immediately with reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1919, height: 994 });
  await page.goto("/en/");
  const edge = page.locator(".hero-bird-edge");
  for (const width of [1920, 1919]) {
    await page.setViewportSize({ width, height: 994 });
    if (width === 1920) await expect(edge).toBeVisible();
    else await expect(edge).toBeHidden();
    expect(await edge.evaluate((node) => node.getAnimations().length)).toBe(0);
  }
});
