// Renders banner.html to docs/src/images/banner.gif, one seamless loop.
// Usage: node design/assets/showcase/readme/render-gif.mjs  (needs ffmpeg on PATH)
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(here, "../../../web/package.json"));
const { chromium } = require("playwright");
const esbuild = require("esbuild");

const FPS = 15;
const out = join(here, "../../../../docs/src/images/banner.gif");

const { outputFiles } = await esbuild.build({
  entryPoints: [join(here, "banner-blob.ts")],
  bundle: true,
  format: "iife",
  globalName: "BannerBlob",
  write: false,
});

const frames = mkdtempSync(join(tmpdir(), "eigin-banner-"));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.goto(pathToFileURL(join(here, "banner.html")).href);
await page.addScriptTag({ content: outputFiles[0].text });
await page.evaluate(() => document.fonts.ready);

const loop = await page.evaluate(() => window.bannerLoop());
const count = Math.round(loop * FPS);
for (let i = 0; i < count; i++) {
  await page.evaluate((t) => window.renderFrame(t), i / FPS);
  await page.screenshot({ path: join(frames, `${String(i).padStart(4, "0")}.png`) });
}
await browser.close();

// One palette for the whole loop, then frame-diffed so still regions cost nothing.
execFileSync("ffmpeg", [
  "-y", "-loglevel", "error", "-framerate", String(FPS), "-i", join(frames, "%04d.png"),
  "-filter_complex",
  "[0:v]split[a][b];[a]palettegen=stats_mode=full:max_colors=128[p];[b][p]paletteuse=dither=none:diff_mode=rectangle",
  "-loop", "0", out,
]);
rmSync(frames, { recursive: true });
console.log(`${count} frames -> ${out}`);
