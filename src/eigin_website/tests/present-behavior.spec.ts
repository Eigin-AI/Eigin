import { expect, test } from "@playwright/test";

const deck = "# First\n\n---\n\n## Second\n\nNote:\nPrivate notes\n\n----\n\n## Third\n";

test("watch recovers after a bad edit and preserves the selected slide", async ({ page }) => {
  let content = deck;
  await page.route(
    (url) => url.pathname === "/watch.md",
    (route) => route.fulfill({ body: content, contentType: "text/plain" }),
  );
  await page.route(
    (url) => url.pathname === "/broken.svg",
    (route) => route.fulfill({ status: 404 }),
  );
  await page.goto("/present/render/?src=/watch.md&slide=3&watch=1");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  content = deck + "\n![Broken](/broken.svg)";
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "error");
  content = deck.replace("Third", "Corrected");
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.locator("body")).toHaveAttribute("data-current-slide", "3");
  await expect(
    page.frameLocator("iframe").getByRole("heading", { name: "Corrected" }),
  ).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("authored scripts and parent-origin access are blocked", async ({ page }) => {
  await page.goto("/present/");
  const svg = encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"/>');
  const markdown = `# Safe heading\n\n<img src="data:image/svg+xml,${svg}" onload="document.body.dataset.compromised=1">\n<script>document.body.dataset.compromised=1</script>`;
  await page
    .locator('input[type="file"]')
    .setInputFiles({ name: "hostile.md", mimeType: "text/plain", buffer: Buffer.from(markdown) });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  await expect(page.frameLocator("iframe").locator("body")).not.toHaveAttribute("data-compromised");
  expect(
    await page
      .frameLocator("iframe")
      .locator("body")
      .evaluate(() => {
        try {
          localStorage.setItem("attack", "1");
          return false;
        } catch {
          return true;
        }
      }),
  ).toBe(true);
});

test("PDF mode lays out every slide and produces a multi-page PDF", async ({
  page,
  browserName,
}, testInfo) => {
  test.skip(browserName !== "chromium", "Playwright PDF generation requires Chromium.");
  await page.addInitScript((markdown) => {
    Object.defineProperty(window, "showDirectoryPicker", {
      value: async () => {
        const directory = await (
          await navigator.storage.getDirectory()
        ).getDirectoryHandle("pdf-deck", { create: true });
        const writer = await (
          await directory.getFileHandle("deck.md", { create: true })
        ).createWritable();
        await writer.write(markdown);
        await writer.close();
        return directory;
      },
    });
  }, deck);
  await page.goto("/present/");
  await page.getByRole("button", { name: "Open folder", exact: true }).click();
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  const printUrl = new URL(page.url());
  printUrl.searchParams.set("print-pdf", "1");
  await page.goto(printUrl.href);
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready", {
    timeout: 15000,
  });
  await expect(page.frameLocator("iframe").locator(".pdf-page")).toHaveCount(3);
  await expect(page.frameLocator("iframe").locator(".slide-frame")).toHaveCount(3);
  const printButton = page.getByRole("button", { name: "Print / Save PDF", exact: true });
  const bounds = (await printButton.boundingBox())!;
  const viewport = await page.evaluate(() => ({ width: innerWidth, height: innerHeight }));
  expect(bounds.x + bounds.width).toBeGreaterThan(viewport.width * 0.9);
  expect(bounds.y + bounds.height).toBeGreaterThan(viewport.height * 0.9);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(viewport.height);
  await page.screenshot({ path: testInfo.outputPath("print-preview.png") });
  await page.emulateMedia({ media: "print" });
  await expect(printButton).toBeHidden();
  await page.emulateMedia({ media: null });
  const pdf = await page.pdf({
    path: testInfo.outputPath("presentation.pdf"),
    preferCSSPageSize: true,
    printBackground: true,
  });
  const pages = pdf.toString("latin1").match(/\/Type\s*\/Page\b/g) ?? [];
  expect(pages).toHaveLength(3);
});
