import { expect, test } from "@playwright/test";

/* Screens behaviour, as rendered in the gallery. */

test("chat rows keep one height whatever the preview says", async ({ page }) => {
  await page.goto("/#/screens/chat-list");

  const rows = page.locator(".chat-row");
  await expect(rows.first()).toBeVisible();

  // Swift reserves two lines for the preview, so a one-line chat is no shorter.
  const heights = await rows.evaluateAll((els) =>
    els.map((el) => Math.round(el.getBoundingClientRect().height)),
  );
  expect(new Set(heights).size).toBe(1);
});

test("the chat screen scrolls its feed, not the phone frame", async ({ page }) => {
  await page.goto("/#/screens/chat");

  const viewport = page.locator(".device-viewport");
  const feed = page.locator(".scroll");
  await expect(feed).toBeVisible();

  // The frame itself never scrolls: the header and composer are pinned.
  const frame = await viewport.evaluate((el) => ({
    scroll: el.scrollHeight,
    client: el.clientHeight,
  }));
  expect(frame.scroll).toBe(frame.client);

  const headerBefore = await page.locator(".nav-header").boundingBox();
  const composerBefore = await page.locator(".composer").boundingBox();
  await feed.evaluate((el) => el.scrollTo(0, el.scrollHeight));
  await expect.poll(async () => feed.evaluate((el) => el.scrollTop)).toBeGreaterThan(0);

  expect(await page.locator(".nav-header").boundingBox()).toEqual(headerBefore);
  expect(await page.locator(".composer").boundingBox()).toEqual(composerBefore);
});

test("the chat feed runs behind the composer", async ({ page }) => {
  await page.goto("/#/screens/chat");

  const overlap = await page.evaluate(() => {
    const scroll = document.querySelector(".scroll")!.getBoundingClientRect();
    const composer = document.querySelector(".composer")!.getBoundingClientRect();
    const reserved = parseFloat(getComputedStyle(document.querySelector(".scroll")!).paddingBottom);
    return { covered: scroll.bottom - composer.top, height: composer.height, reserved };
  });

  // The bar sits over the feed, and the feed reserves its height beneath.
  expect(overlap.covered).toBeGreaterThan(0);
  expect(overlap.reserved).toBeGreaterThanOrEqual(overlap.height);
});

test("the call screen wears the phone's chrome and respects the island's edges", async ({
  page,
}) => {
  await page.goto("/#/screens/call");

  // Every screen is shown in a whole phone, chrome and all.
  await expect(page.locator(".status-bar")).toBeVisible();
  await expect(page.locator(".home-indicator")).toHaveCount(1);

  const insets = () =>
    page.locator(".device-viewport").evaluate((el) => {
      const style = getComputedStyle(el);
      return { left: style.paddingLeft, right: style.paddingRight };
    });

  expect(await insets()).toEqual({ left: "0px", right: "0px" });

  await page.getByRole("radio", { name: "Landscape" }).click();
  await expect.poll(insets).toEqual({ left: "59px", right: "59px" });
});

test("a sheet screen opens over the screen it belongs to", async ({ page }) => {
  await page.goto("/#/screens/provider-select");

  // The host is behind it, so the sheet reads as presented rather than routed.
  const frame = page.locator(".device-frame");
  await expect(frame.getByText("Add Provider")).toBeAttached();
  await expect(frame.getByText("AI Provider")).toBeVisible();
});

test("a screen's demo controls sit on the stage, not on the phone", async ({ page }) => {
  await page.goto("/#/screens/mcp-server");

  // Beside the device pickers, so the phone shows only the design.
  await expect(page.locator(".device-picker").getByRole("radio", { name: "error" })).toBeVisible();
  await expect(page.locator(".device-screen").getByRole("radio", { name: "error" })).toHaveCount(0);
});

test("the api-key fold rolls open and the sheet grows with it", async ({ page }) => {
  await page.goto("/#/screens/provider-select");

  const sheet = page.locator(".sheet");
  const open = (await sheet.boundingBox())!.height;

  await page.getByText("Or connect with an API key").click();
  await expect(page.locator(".keys")).toHaveCount(0);

  const closed = (await sheet.boundingBox())!.height;
  expect(closed).toBeLessThan(open);
});

test("a page presented modally takes the room and brings its own header", async ({ page }) => {
  await page.goto("/#/screens/add-mcp-server");

  // Swift uses a plain `.sheet` here, so the card fills rather than hugging...
  const room = await page.evaluate(() => {
    const screen = document.querySelector(".device-screen")!.getBoundingClientRect();
    const sheet = document.querySelector(".sheet")!.getBoundingClientRect();
    return sheet.height / screen.height;
  });
  expect(room).toBeGreaterThan(0.85);

  // ...and the form's navigation header stands in for the sheet header.
  await expect(page.locator(".sheet .grabber")).toHaveCount(0);
  await expect(page.locator(".sheet").getByText("Add MCP Server")).toBeVisible();
});

test("the agent's face arrives just after its body", async ({ page }) => {
  await page.goto("/#/screens/call");

  const entry = await page.evaluate(() => {
    const emoji = document.querySelector(".emoji")!;
    const animation = emoji.getAnimations()[0];
    const timing = animation.effect!.getTiming();
    animation.currentTime = 0;
    const before = getComputedStyle(emoji).scale;
    animation.currentTime = Number(timing.delay) + Number(timing.duration);
    return { delay: Number(timing.delay), before, after: getComputedStyle(emoji).scale };
  });

  // The blob holds 0.35s then takes 0.4s, so the face must not start with it.
  expect(entry.delay).toBeGreaterThan(350);
  expect(entry.before).toBe("0");
  expect(entry.after).toBe("1");
});

test("the grid overlay tints the space it reserves, over a real screen", async ({ page }) => {
  await page.goto("/#/screens/settings");
  await expect(page.locator(".grid-overlay")).toHaveCount(0);

  await page.getByRole("button", { name: "Show the grid" }).click();
  const overlay = page.locator(".grid-overlay");
  await expect(overlay).toBeVisible();

  // Margins are drawn to the tokens the scope resolved, not to guesses.
  const drawn = await page.evaluate(() => {
    const scope = document.querySelector(".device-screen .eigin-grid")!;
    const read = (name: string) => getComputedStyle(scope).getPropertyValue(name).trim();
    const width = (selector: string) =>
      Math.round(document.querySelector(selector)!.getBoundingClientRect().width);
    return {
      outer: { drawn: width(".grid-overlay .outer"), token: read("--grid-outer") },
      inner: { drawn: width(".grid-overlay .inner"), token: read("--grid-inner") },
    };
  });

  expect(drawn.outer.drawn).toBe(parseInt(drawn.outer.token, 10));
  expect(drawn.inner.drawn).toBe(parseInt(drawn.inner.token, 10));
});
