import { expect, test } from "@playwright/test";
import { zipSync, strToU8 } from "fflate";

const image =
  '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="12" fill="red"/></svg>';
function localDeck(title: string) {
  return {
    name: "deck.zip",
    mimeType: "application/zip",
    buffer: Buffer.from(
      zipSync({
        "deck/deck.md": strToU8(
          `# Cover\n\n---\n\n## ${title}\n\n![Local media](media/dot.svg)\n\n----\n\n## Vertical slide\n`,
        ),
        "deck/media/dot.svg": strToU8(image),
      }),
    ),
  };
}

test("agent renders local ZIP bytes, selects a slide, and previews edits without hosting", async ({
  page,
}, testInfo) => {
  const writes: string[] = [];
  let defaultSourceRequests = 0;
  page.on("request", (request) => {
    if (["POST", "PUT", "PATCH"].includes(request.method())) writes.push(request.url());
    if (new URL(request.url()).pathname.endsWith("/deck.md")) defaultSourceRequests++;
  });
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto("/present/render/?slide=2");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "idle");
  await expect(page.getByRole("heading", { name: "Render a local deck" })).toBeVisible();
  const input = page.getByLabel("Choose a presentation file");
  await expect(input).toBeEnabled();
  await input.setInputFiles(localDeck("Initial preview"));
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.locator("body")).toHaveAttribute("data-total-slides", "3");
  await expect(page.locator("body")).toHaveAttribute("data-current-slide", "2");
  expect(new URL(page.url()).searchParams.get("slide")).toBe("2");
  const frame = page.frameLocator("iframe");
  await expect(frame.getByRole("heading", { name: "Initial preview" })).toBeVisible();
  await expect(frame.getByRole("img", { name: "Local media" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Render a local deck" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Menu", exact: true })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath("local-slide-2.png") });

  await input.setInputFiles(localDeck("Edited preview"));
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.locator("body")).toHaveAttribute("data-current-slide", "2");
  await expect(frame.getByRole("heading", { name: "Edited preview" })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("edited-slide-2.png") });
  expect(defaultSourceRequests).toBe(0);
  expect(writes).toEqual([]);
});

test("agent can replace a failed local Markdown preview through the same input", async ({
  page,
}) => {
  await page.route(
    (url) => url.pathname.endsWith("/missing.png"),
    (route) => route.fulfill({ status: 404 }),
  );
  await page.goto("/present/render/");
  const input = page.getByLabel("Choose a presentation file");
  await expect(input).toBeEnabled();
  await input.setInputFiles({
    name: "deck.md",
    mimeType: "text/plain",
    buffer: Buffer.from("# Broken\n\n![Missing](missing.png)"),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "error");
  await expect(page.getByRole("alert")).toContainText("Could not load image");
  await input.setInputFiles({
    name: "deck.md",
    mimeType: "text/plain",
    buffer: Buffer.from("# Corrected"),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "Corrected" }),
  ).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("a replacement file supersedes a deck still waiting for an image", async ({ page }) => {
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route("**/slow.svg", async (route) => {
    await gate;
    await route.fulfill({ status: 404 });
  });
  await page.goto("/present/render/");
  const input = page.getByLabel("Choose a presentation file");
  await expect(input).toBeEnabled();
  const requested = page.waitForRequest("**/slow.svg");
  await input.setInputFiles({
    name: "deck.md",
    mimeType: "text/plain",
    buffer: Buffer.from("# Stale deck\n\n![Slow](/slow.svg)"),
  });
  await requested;
  await input.setInputFiles({
    name: "deck.md",
    mimeType: "text/plain",
    buffer: Buffer.from("# Latest deck"),
  });
  try {
    await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready", {
      timeout: 5000,
    });
    await expect(
      page.frameLocator("iframe").getByRole("heading", { name: "Latest deck" }),
    ).toBeVisible();
  } finally {
    release();
  }
  await expect(page.getByRole("alert")).toHaveCount(0);
});
