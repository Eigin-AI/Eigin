import { expect, test } from "@playwright/test";

test("generated website artwork is discoverable and usable by local slides", async ({
  page,
  request,
}, testInfo) => {
  await page.goto("/present/guide/icons/");
  await expect(
    page.getByRole("heading", { name: "Icons and illustrations", exact: true }),
  ).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("icon-catalogue.png") });
  await page.getByPlaceholder("Search icons and illustrations").fill("illustration/hero-bird");
  const link = page.getByRole("link", {
    name: "/assets/design-icons/illustration/hero-bird.svg",
    exact: true,
  });
  await expect(link).toBeVisible();
  const path = (await link.getAttribute("href"))!;
  const asset = await request.get(path);
  expect(asset.ok()).toBe(true);
  expect(asset.headers()["content-type"]).toContain("image/svg+xml");
  const absolute = new URL(path, page.url()).href;
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto("/present/render/");
  const input = page.getByLabel("Choose a presentation file");
  await expect(input).toBeEnabled();
  const markdown = `# Shared artwork\n\n<img src="${path}" width="100" alt="Generated illustration">\n<img src="${absolute}" width="100" alt="Absolute illustration">\n<span class="icon" style="--shape:url('/assets/design-icons/functional/search.svg')" aria-label="Search icon"></span>\n\n\`${path}\`\n\n\`\`\`html\n<img src="${path}">\n\`\`\``;
  await input.setInputFiles({
    name: "deck.md",
    mimeType: "text/plain",
    buffer: Buffer.from(markdown),
  });
  await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready");
  const frame = page.frameLocator("iframe");
  await expect(frame.getByRole("img", { name: "Generated illustration" })).toBeVisible();
  await expect(frame.getByRole("img", { name: "Absolute illustration" })).toHaveAttribute(
    "src",
    absolute,
  );
  await expect(frame.locator("pre code")).toContainText(`<img src="${path}">`);
  expect(await frame.locator(".icon").evaluate((el) => getComputedStyle(el).maskImage)).toContain(
    "data:image/svg+xml;base64,",
  );
  await page.screenshot({ path: testInfo.outputPath("design-artwork.png") });
});
