// Renders each slide of deck.md to a PNG in docs/src/images/ via www.eigin.ai/present/render.
// Usage: node design/assets/readme/deck/render.mjs
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const images = join(here, "../../../../docs/src/images");
const require = createRequire(join(here, "../../../web/package.json"));
const { chromium } = require("playwright");

// Slide number (1-based) to output file name.
const slides = { 1: "system.png" };
const port = 8097;
const types = { ".md": "text/markdown", ".png": "image/png", ".svg": "image/svg+xml" };

const server = createServer(async (req, res) => {
  try {
    const path = join(here, decodeURIComponent(new URL(req.url, "http://x").pathname));
    const body = await readFile(path);
    res.writeHead(200, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Private-Network": "true",
      "Content-Type": types[extname(path)] ?? "application/octet-stream",
    });
    res.end(body);
  } catch {
    res.writeHead(404, { "Access-Control-Allow-Origin": "*" });
    res.end();
  }
}).listen(port);

const browser = await chromium.launch({
  // The public renderer fetches the deck from localhost, which Chrome blocks by default.
  args: ["--disable-features=LocalNetworkAccessChecks,BlockInsecurePrivateNetworkRequests"],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 });
for (const [slide, file] of Object.entries(slides)) {
  const src = encodeURIComponent(`http://localhost:${port}/deck.md`);
  await page.goto(`https://www.eigin.ai/present/render/?src=${src}&slide=${slide}`);
  await page.waitForSelector('body[data-render-status="ready"]');
  await page.waitForTimeout(900); // reveal cross-fades slide backgrounds
  await page.screenshot({ path: join(images, file) });
  console.log(`slide ${slide} -> ${file}`);
}
await browser.close();
server.close();
