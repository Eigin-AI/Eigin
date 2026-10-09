// Renders the gallery's registered showcase shots to design/assets/showcase/.
// Usage: node scripts/showcase/cli.mjs [--png] [shot-id…]   (from design/web; all shots when none named)
import { chromium } from "@playwright/test";
import { createServer } from "vite";
import { assetFile, displayPath, renderShot } from "./render.mjs";

const args = process.argv.slice(2);
const format = args.includes("--png") ? "png" : "jpg";
const wanted = args.filter((arg) => arg !== "--png");

// A private server on a free port, so a running gallery is left alone.
const server = await createServer({ server: { port: 0 }, logLevel: "error" });
await server.listen();
const browser = await chromium.launch();

try {
  const origin = server.resolvedUrls.local[0];
  const shots = await server.ssrLoadModule("/src/gallery/showcase/shots.ts");
  const { renderHash } = await server.ssrLoadModule("/src/gallery/showcase/shotUrl.ts");

  const unknown = wanted.filter((id) => !shots.shotEntries.some((entry) => entry.id === id));
  if (unknown.length) throw new Error(`Unknown shots: ${unknown.join(", ")}`);
  const selected = shots.shotEntries.filter(
    (entry) => wanted.length === 0 || wanted.includes(entry.id),
  );

  for (const entry of selected) {
    const size = shots.sizeOf(entry);
    const file = assetFile(shots.assetPath(entry, format));
    await renderShot({
      origin,
      hash: renderHash(entry.id, entry, entry),
      width: size.width,
      height: size.height,
      out: file,
      browser,
    });
    console.log(`${entry.id} -> ${displayPath(file)}`);
  }
} finally {
  await browser.close();
  await server.close();
}
