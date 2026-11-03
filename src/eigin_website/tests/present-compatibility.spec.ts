import { expect, test } from "@playwright/test";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { zipSync } from "fflate";

// Opt-in: private presentation content stays outside the repository and build.
const root = process.env.PRESENTATIONS_DIR;
for (const name of ["breakfast-club", "evu-pilot-kickoff", "dtu-digital-tech-summit"]) {
  test(`existing ${name} deck renders with its original media and fonts`, async ({
    page,
  }, testInfo) => {
    test.skip(!root, "Set PRESENTATIONS_DIR to the existing presentations checkout.");
    const files: Record<string, Uint8Array> = {};
    async function collect(directory: string, prefix = "") {
      for (const entry of await readdir(directory, { withFileTypes: true })) {
        if (entry.name.startsWith(".")) continue;
        const path = join(directory, entry.name);
        if (entry.isDirectory()) await collect(path, prefix + entry.name + "/");
        else if (/\.(md|png|jpe?g|gif|svg|webp|avif|mp4|webm|mov|m4v|pdf)$/i.test(entry.name))
          files[prefix + entry.name] = await readFile(path);
      }
    }
    await collect(join(root!, name));
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto("/present/?transition=none");
    await page.locator('input[type="file"]').setInputFiles({
      name: name + ".zip",
      mimeType: "application/zip",
      buffer: Buffer.from(zipSync(files)),
    });
    await expect(page.locator("body")).toHaveAttribute("data-render-status", "ready", {
      timeout: 30000,
    });
    const frame = page.frameLocator("iframe");
    expect(await frame.locator("body").evaluate(() => document.fonts.size)).toBeGreaterThan(8);
    expect(
      await frame.locator("body").evaluate(() => document.fonts.check('400 24px "FiveSerifText"')),
    ).toBe(true);
    await page.screenshot({ path: testInfo.outputPath(name + "-cover.png") });
    await frame.locator(".reveal").click({ position: { x: 600, y: 350 } });
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("body")).not.toHaveAttribute("data-current-slide", "1");
    await page.screenshot({ path: testInfo.outputPath(name + "-content.png") });
  });
}
