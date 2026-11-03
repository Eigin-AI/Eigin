import { expect, test } from "@playwright/test";
import { zipSync, strToU8 } from "fflate";

const deck = `<!-- .slide: class="layout-cover" data-art="bird" -->
# A working deck

A small cover.

---

<!-- .slide: class="theme-light" -->
## Second slide

![Example](media/dot.svg)

Note:
These notes stay out of screenshots.

----

## Vertical slide

<style>.custom { color: red; }</style>
<div class="custom">Custom HTML</div>
`;
const image =
  '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="12" fill="red"/></svg>';

test.beforeEach(async ({ page }) => {
  await page.route(
    (url) => url.pathname === "/fixtures/deck.md",
    (route) => route.fulfill({ body: deck, contentType: "text/plain" }),
  );
  await page.route("**/fixtures/media/dot.svg", (route) =>
    route.fulfill({ body: image, contentType: "image/svg+xml" }),
  );
});

test("direct renderer URL preserves flat slide selection and readiness after refresh", async ({
  page,
}) => {
  await page.goto("/present/render/?src=/fixtures/deck.md&slide=3");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.locator("body")).toHaveAttribute("data-total-slides", "3");
  await expect(page.locator("body")).toHaveAttribute("data-current-slide", "3");
  await expect(page.frameLocator("iframe").locator("section.present:not(.stack) h2")).toHaveText(
    "Vertical slide",
  );
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "noindex, nofollow");
  await page.reload();
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.locator("body")).toHaveAttribute("data-current-slide", "3");
});

test("nested local ZIP resolves media and exposes notes without granting origin access", async ({
  page,
}) => {
  await page.goto("/present/");
  await page.locator('input[type="file"]').setInputFiles({
    name: "deck.zip",
    mimeType: "application/zip",
    buffer: Buffer.from(
      zipSync({ "nested/deck.md": strToU8(deck), "nested/media/dot.svg": strToU8(image) }),
    ),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  const frame = page.frameLocator("iframe");
  await expect(frame.locator(".slide-frame")).toHaveCount(3);
  const isolation = await frame.locator("body").evaluate(() => {
    try {
      return window.parent.document.title;
    } catch {
      return "blocked";
    }
  });
  expect(isolation).toBe("blocked");
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  await page.getByRole("button", { name: "Speaker notes", exact: true }).click();
  await expect(page.getByRole("complementary", { name: "Speaker notes" })).toBeVisible();
});

test("missing sources report a stable error", async ({ page }) => {
  await page.route(
    (url) => url.pathname === "/missing.md",
    (route) => route.fulfill({ status: 404 }),
  );
  await page.goto("/present/render/?src=/missing.md");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "error");
  await expect(page.getByRole("alert")).toContainText("HTTP 404");
});

test("guide prerenders the authoring and agent contracts", async ({ request }) => {
  const response = await request.get("/present/guide/");
  expect(response.status()).toBe(200);
  const html = await response.text();
  expect(html).toContain("data-render-status");
  expect(html).toContain('content="noindex, nofollow"');
  expect(html).toContain("Slide syntax");
});
