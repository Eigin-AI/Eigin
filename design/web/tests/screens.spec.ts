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
  await page.goto("/#/screens/chat?long");
  await page.evaluate(() => document.fonts.ready);

  const viewport = page.locator(".device-viewport");
  const feed = page.locator(".device-screen .scroll");
  await expect(feed).toBeVisible();

  // The frame itself never scrolls: the header and composer are pinned.
  const frame = await viewport.evaluate((el) => ({
    scroll: el.scrollHeight,
    client: el.clientHeight,
  }));
  expect(frame.scroll).toBe(frame.client);

  const headerBefore = await page.locator(".nav-header").boundingBox();
  const composer = page.locator(".device-screen .region > .footer");
  await expect(composer.getByPlaceholder("Chat with Eigin")).toBeAttached();
  const composerBefore = await composer.boundingBox();
  await feed.evaluate((el) => el.scrollTo(0, el.scrollHeight));
  await expect.poll(async () => feed.evaluate((el) => el.scrollTop)).toBeGreaterThan(0);

  expect(await page.locator(".nav-header").boundingBox()).toEqual(headerBefore);
  expect(await composer.boundingBox()).toEqual(composerBefore);
});

test("the chat feed runs behind the composer and reserves its height", async ({ page }) => {
  await page.goto("/#/screens/chat?long");
  await expect(page.locator(".device-screen .region > .footer")).toBeVisible();
  await page.evaluate(() => document.fonts.ready);

  const overlap = () =>
    page.locator(".device-screen .scroll").evaluate((el) => {
      const scroll = el.getBoundingClientRect();
      const footer = el.parentElement!.querySelector(".footer")!.getBoundingClientRect();
      const scale = scroll.height / el.clientHeight;
      return {
        covered: (scroll.bottom - footer.top) / scale,
        height: footer.height / scale,
        reserved: parseFloat(getComputedStyle(el).paddingBottom),
      };
    });

  await expect.poll(async () => (await overlap()).covered).toBeGreaterThan(0);
  // Resize observation updates the reserved space after the footer lays out.
  await expect
    .poll(async () => {
      const { reserved, height } = await overlap();
      return reserved - height;
    })
    .toBeGreaterThanOrEqual(0);
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
  await page.goto("/#/screens/connect-integration");

  const failure = page
    .locator(".device-picker")
    .getByRole("radio", { name: "failed", exact: true });
  await expect(failure).toBeVisible();
  await expect(page.locator(".device-screen").getByRole("radio", { name: "failed" })).toHaveCount(
    0,
  );

  await failure.click();
  await expect(page.getByRole("dialog").getByText("The sign-in did not finish")).toBeVisible();
});

test("provider search filters connection methods and keeps the address fallback", async ({
  page,
}) => {
  await page.goto("/#/screens/provider-select");

  const sheet = page.getByRole("dialog");
  const signIn = sheet.locator("section").filter({
    has: page.getByRole("heading", { name: "Sign in", exact: true }),
  });
  const apiKey = sheet.locator("section").filter({
    has: page.getByRole("heading", { name: "Paste an API key", exact: true }),
  });
  const address = sheet.getByRole("button", { name: "Connect by address" });
  const search = sheet.getByPlaceholder("Search providers");

  await expect(signIn.getByRole("button", { name: "OpenAI", exact: true })).toBeVisible();
  await expect(apiKey.getByRole("button", { name: "OpenAI", exact: true })).toBeVisible();
  await expect(sheet.getByRole("button", { name: "Anthropic", exact: true })).toHaveCount(0);

  await search.fill("Google");
  await expect(signIn).toHaveCount(0);
  await expect(apiKey.getByRole("button", { name: "Google", exact: true })).toBeVisible();
  await expect(sheet.getByRole("button", { name: "OpenAI", exact: true })).toHaveCount(0);
  await expect(address).toBeVisible();

  await search.fill("Unknown provider");
  await expect(signIn).toHaveCount(0);
  await expect(apiKey).toHaveCount(0);
  await expect(sheet.getByText("We don't know that one", { exact: true })).toBeVisible();
  await expect(address).toBeVisible();

  await search.clear();
  await expect(signIn.getByRole("button", { name: "OpenAI", exact: true })).toBeVisible();
  await expect(apiKey.getByRole("button", { name: "OpenAI", exact: true })).toBeVisible();
});

test("an integration form scrolls below its pinned sheet header", async ({ page }) => {
  await page.goto("/#/screens/connect-integration");
  await page
    .locator(".device-picker")
    .getByRole("radio", { name: "mail account", exact: true })
    .click();
  await page.getByRole("radio", { name: "Landscape", exact: true }).click();

  const sheet = page.getByRole("dialog");
  const header = sheet.locator("header");
  await expect(header.getByRole("heading", { name: "Other email" })).toBeVisible();
  const scroll = sheet.locator(".scroll");
  await expect(header.getByRole("button", { name: "Dismiss" })).toBeVisible();
  await expect(sheet.locator(".grabber")).toBeVisible();
  for (const label of ["Email address", "App password", "IMAP server", "SMTP server"]) {
    await expect(sheet.getByLabel(label, { exact: true })).toBeAttached();
  }
  await page.evaluate(() => document.fonts.ready);
  await expect
    .poll(() => sheet.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m42))
    .toBe(0);

  const before = await header.boundingBox();
  await scroll.evaluate((el) => el.scrollTo(0, el.scrollHeight));
  await expect.poll(() => scroll.evaluate((el) => el.scrollTop)).toBeGreaterThan(0);
  expect(await header.boundingBox()).toEqual(before);
  const action = await sheet.getByRole("button", { name: "Connect", exact: true }).boundingBox();
  const body = await scroll.boundingBox();
  expect(action!.y).toBeGreaterThanOrEqual(before!.y + before!.height - 1);
  expect(action!.y + action!.height).toBeLessThanOrEqual(body!.y + body!.height + 1);
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
