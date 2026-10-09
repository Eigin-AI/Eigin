import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "@playwright/test";
import { optionCategories } from "../src/gallery/showcase/conversation";
import { backgrounds, shotEntries, sizeOf } from "../src/gallery/showcase/shots";
import { renderHash } from "../src/gallery/showcase/shotUrl";
import { renderShot } from "../scripts/showcase/render.mjs";

/* Showcase shots: composed in the gallery, rendered alone for export. */

for (const entry of shotEntries) {
  test(`${entry.id} renders alone at its pixel size`, async ({ page }) => {
    const errors: Error[] = [];
    page.on("pageerror", (error) => errors.push(error));
    await page.goto(`/${renderHash(entry.id, entry, entry)}`);
    await page.waitForSelector("body[data-showcase-ready]");

    const size = sizeOf(entry);
    const box = await page.locator(".shot-canvas").boundingBox();
    expect(box).toMatchObject({ x: 0, y: 0, width: size.width, height: size.height });
    await expect(page.locator(".device-screen")).toBeVisible();
    await expect(page.locator(".sidebar")).toHaveCount(0);
    expect(errors).toEqual([]);
  });
}

test("the URL overrides what a shot shows", async ({ page }) => {
  const [entry] = shotEntries;
  const light = backgrounds.find((background) => background.id === "light")!;
  const shot = { ...entry, layout: "flat" as const, background: "light", headline: "Hello" };
  await page.goto(`/${renderHash(entry.id, shot, entry)}`);
  await page.waitForSelector("body[data-showcase-ready]");

  await expect(page.locator('.shot-canvas[data-layout="flat"]')).toBeVisible();
  await expect(page.locator(".headline")).toHaveText("Hello");
  const fill = await page
    .locator(".shot-canvas")
    .evaluate((el) => el.style.getPropertyValue("--fill"));
  expect(fill).toBe(light.fill);
});

test("the stage keeps the URL in step with its controls", async ({ page }) => {
  await page.goto("/#/showcase/hero");
  await page.getByRole("radio", { name: "Flat" }).click();
  await expect(page).toHaveURL(/#\/showcase\/hero\?layout=flat$/);
  await expect(page.locator('.shot-canvas[data-layout="flat"]')).toBeVisible();
});

test("an export is the shot's size at the chosen scale, in the chosen format", async ({
  baseURL,
}, testInfo) => {
  test.skip(testInfo.project.name !== "chromium", "Export always renders with Chromium.");
  const [entry] = shotEntries;
  const size = sizeOf(entry);
  const shot = {
    origin: baseURL!,
    hash: renderHash(entry.id, entry, entry),
    width: size.width,
    height: size.height,
  };
  const dir = await mkdtemp(join(tmpdir(), "eigin-showcase-"));
  try {
    // A .png path writes a PNG; its width and height sit at bytes 16 and 20.
    await renderShot({ ...shot, scale: 2, out: join(dir, "shot.png") });
    const png = await readFile(join(dir, "shot.png"));
    expect([png.readUInt32BE(16), png.readUInt32BE(20)]).toEqual([size.width * 2, size.height * 2]);

    // Without a path the image comes back; a JPEG starts with FF D8.
    const jpeg = await renderShot({ ...shot, format: "jpg" });
    expect([jpeg[0], jpeg[1]]).toEqual([0xff, 0xd8]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("dragging the preview moves the phone", async ({ page }) => {
  await page.goto("/#/showcase/hero");
  const preview = page.locator(".shot-scaled");
  const box = (await preview.boundingBox())!;
  const device = page.locator(".shot-canvas .device");
  const before = (await device.boundingBox())!;

  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 - box.width / 10, box.y + box.height / 2, {
    steps: 5,
  });
  await page.mouse.up();

  // A tenth of the preview's width is a tenth of the canvas, whatever the zoom.
  await expect(page).toHaveURL(/[?&]x=-10(&|$)/);
  expect((await device.boundingBox())!.x).toBeLessThan(before.x);
});

test("the headline holds its spot whatever the phone does", async ({ page }) => {
  const [entry] = shotEntries;
  const headlineBox = async (placement: { x: number; y: number; scale: number }) => {
    await page.goto(`/${renderHash(entry.id, { ...entry, placement }, entry)}`);
    await page.waitForSelector("body[data-showcase-ready]");
    return page.locator(".headline").boundingBox();
  };

  const resting = await headlineBox({ x: 0, y: 0, scale: 1 });
  expect(await headlineBox({ x: -12, y: 8, scale: 1.6 })).toEqual(resting);
});

test("returns in the headline are its line breaks", async ({ page }) => {
  const [entry] = shotEntries;
  const shot = { ...entry, headline: "One\nTwo words\nThree" };
  await page.goto(`/${renderHash(entry.id, shot, entry)}`);
  await page.waitForSelector("body[data-showcase-ready]");

  const lines = await page.locator(".headline").evaluate((el) => {
    const range = document.createRange();
    range.selectNodeContents(el);
    return new Set([...range.getClientRects()].map((rect) => Math.round(rect.top))).size;
  });
  expect(lines).toBe(3);
});

for (const at of ["bottom-left", "top-right"] as const) {
  test(`a ${at} headline sits as far from the side as from the edge`, async ({ page }) => {
    const [entry] = shotEntries;
    await page.goto(`/${renderHash(entry.id, { ...entry, headlineAt: at }, entry)}`);
    await page.waitForSelector("body[data-showcase-ready]");

    // The headline's box is trimmed to its capitals, so it measures the letters.
    const gaps = await page.locator(".headline").evaluate((el) => {
      const text = el.getBoundingClientRect();
      const canvas = el.closest(".shot-canvas")!.getBoundingClientRect();
      return {
        side: Math.min(text.left - canvas.left, canvas.right - text.right),
        edge: Math.min(text.top - canvas.top, canvas.bottom - text.bottom),
      };
    });
    expect(Math.abs(gaps.side - gaps.edge)).toBeLessThan(4);
  });
}

test("an export waits for a sheet to finish rising", async ({ page }) => {
  const [entry] = shotEntries;
  const shot = { ...entry, screen: "provider-select", layout: "flat" as const };
  await page.goto(`/${renderHash(entry.id, shot, entry)}`);
  await page.waitForSelector("body[data-showcase-ready]");

  // At rest, the sheet's transform has run its course: no offset left.
  const transform = await page
    .locator(".device-screen .sheet")
    .evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m42);
  expect(transform).toBe(0);
});

test("the chat builder draws the conversation you write", async ({ page }) => {
  await page.goto("/#/showcase/chat-builder");
  const phone = page.locator(".shot-canvas .device-screen");

  await page.getByRole("button", { name: "Add turn" }).click();
  await page.locator(".turn textarea").last().fill("Make it rain on Sunday, please.");
  await expect(phone.getByText("Make it rain on Sunday, please.")).toBeVisible();

  // The URL carries the conversation, so render mode draws the same feed.
  const hash = new URL(page.url()).hash;
  await page.goto(`/${hash}&render`);
  await page.waitForSelector("body[data-showcase-ready]");
  await expect(page.getByText("Make it rain on Sunday, please.")).toBeVisible();
  await expect(page.locator(".options-group")).toHaveCount(1);
});

test("an option's category picks its illustration, as in the app", async ({ page }) => {
  const draw = async (line: string) => {
    const chat = JSON.stringify([{ kind: "options", text: line }]);
    await page.goto(`/#/showcase/chat-builder?render&chat=${encodeURIComponent(chat)}`);
    await page.waitForSelector("body[data-showcase-ready]");
    return page.locator(".options-group .eigin-icon").first().innerHTML();
  };

  const care = await draw("Rest up | Take the evening off | care");
  expect(care).toBe(await draw("Rest up | Take the evening off | Care"));
  expect(care).not.toBe(await draw("Rest up | Take the evening off | rest"));
  expect(care).not.toBe(await draw("Rest up | Take the evening off"));
});

/* The category map mirrors AgentOptions.swift in the app; this pins the two
   together so neither drifts without the other. */
test("the option categories mirror the app's map", async () => {
  const swift = await readFile(
    new URL("../../../src/eigin_ios/Sources/Chat/Models/AgentOptions.swift", import.meta.url),
    "utf8",
  );
  const inApp = Object.fromEntries(
    [...swift.matchAll(/case \.(\w+): Iconography\.Illustration\.(\w+)/g)].map(
      ([, category, icon]) => [category, `illustration/${icon.replace(/([a-z])(\d)/g, "$1-$2")}`],
    ),
  );
  expect(optionCategories).toEqual(inApp);
});

test("option cards on a tilted phone keep their text unfaded", async ({ page }) => {
  await page.goto("/#/showcase/chat-builder?render");
  await page.waitForSelector("body[data-showcase-ready]");

  // A tilt inflates on-screen boxes; the cards' own text still fits.
  await expect(page.locator(".visual .text").first()).toBeVisible();
  await expect(page.locator(".visual .text.is-scrollable")).toHaveCount(0);
});

test("the preview stays in view as the controls scroll", async ({ page }) => {
  await page.setViewportSize({ width: 1400, height: 800 });
  await page.goto("/#/showcase/chat-builder");
  await expect(page.locator(".shot-canvas")).toBeVisible();

  const title = page.locator(".panel-title");
  await title.hover();
  await page.mouse.wheel(0, 5000);
  await expect(title).not.toBeInViewport();
  const box = (await page.locator(".shot-scaled").boundingBox())!;
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(box.y).toBeLessThan(100);
});

test("the scroll fader sets the phone's scroll for the export", async ({ page }) => {
  await page.goto("/#/showcase/chat-builder");
  await expect(
    page.locator(".shot-canvas .device-screen").getByText("Keep it loose"),
  ).toBeVisible();
  await page.getByLabel(/^Scroll/).fill("0");
  await expect(page).toHaveURL(/[?&]scroll=0(&|$)/);
  await expect(
    page.locator(".shot-canvas").getByText("Can you plan a slow Saturday"),
  ).toBeVisible();

  await page.goto(`/${new URL(page.url()).hash}&render`);
  await page.waitForSelector("body[data-showcase-ready]");
  await expect(page.getByText("Can you plan a slow Saturday")).toBeInViewport();
});

test("scrolling the phone in the preview is kept in the export", async ({ page }) => {
  await page.goto("/#/showcase/chat-builder");
  const screen = page.locator(".shot-canvas .device-screen");
  await expect(screen.getByText("Keep it loose")).toBeVisible();

  // The builder starts on the latest turn; scroll back up to the question.
  await screen.hover();
  await page.mouse.wheel(0, -2000);
  await expect(page).toHaveURL(/[?&]scroll=0(&|$)/);

  await page.goto(`/${new URL(page.url()).hash}&render`);
  await page.waitForSelector("body[data-showcase-ready]");
  await expect(page.getByText("Can you plan a slow Saturday")).toBeInViewport();
});

test("a scroll partway down lands at the same share of the screen in the export", async ({
  page,
}) => {
  await page.goto("/#/showcase/chat-builder");
  const screen = page.locator(".shot-canvas .device-screen");
  await expect(screen.getByText("Keep it loose")).toBeVisible();
  await screen.hover();
  await page.mouse.wheel(0, -2000);
  await expect(page).toHaveURL(/[?&]scroll=0(&|$)/);
  await page.mouse.wheel(0, 40);
  const scrollOf = () => Number(new URL(page.url().replace("#", "")).searchParams.get("scroll"));
  await expect.poll(scrollOf).toBeGreaterThan(5);
  const percent = scrollOf();
  expect(percent).toBeLessThan(95);

  await page.goto(`/${new URL(page.url()).hash}&render`);
  await page.waitForSelector("body[data-showcase-ready]");
  const rendered = await page.evaluate(() => {
    const scroller = [...document.querySelectorAll<HTMLElement>(".device-screen *")].find(
      (el) => getComputedStyle(el).overflowY === "auto" && el.scrollHeight > el.clientHeight + 1,
    )!;
    return (scroller.scrollTop / (scroller.scrollHeight - scroller.clientHeight)) * 100;
  });
  expect(Math.abs(rendered - percent)).toBeLessThan(1);
});

test("the phone's text in the preview wraps as it does in the export", async ({ page }) => {
  // The share of the screen the first message takes, which grows if it wraps more.
  const messageShare = async () => {
    const screen = page.locator(".shot-canvas .device-screen");
    const message = screen.getByText("Can you plan a slow Saturday");
    await expect(message).toBeVisible();
    const [outer, inner] = [(await screen.boundingBox())!, (await message.boundingBox())!];
    return inner.height / outer.height;
  };
  await page.goto("/#/showcase/chat-builder?scroll=0");
  const preview = await messageShare();
  await page.goto("/#/showcase/chat-builder?scroll=0&render");
  await page.waitForSelector("body[data-showcase-ready]");
  expect(preview).toBeCloseTo(await messageShare(), 2);
});

test("moving the light moves the glare on the glass", async ({ page }) => {
  const [entry] = shotEntries;
  const glareAt = async (angle: number) => {
    const shot = { ...entry, light: { angle, height: 35 } };
    await page.goto(`/${renderHash(entry.id, shot, entry)}`);
    await page.waitForSelector("body[data-showcase-ready]");
    return page
      .locator(".device-3d")
      .evaluate((el) => [
        el.style.getPropertyValue("--glare-x"),
        el.style.getPropertyValue("--glare-y"),
      ]);
  };

  expect(await glareAt(-40)).not.toEqual(await glareAt(40));
});
