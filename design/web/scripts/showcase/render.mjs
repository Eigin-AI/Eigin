// Renders one showcase shot from a running gallery.
import { mkdir } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

/** Where every showcase asset lives. Nothing is written outside it. */
export const assetsDir = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../assets/showcase",
);

/**
 * Resolves a path under `assetsDir`, refusing anything that escapes it.
 * @param {string} path
 */
export function assetFile(path) {
  const file = resolve(assetsDir, path);
  const inside = relative(assetsDir, file);
  if (!/\.(png|jpg)$/.test(file) || inside.startsWith("..") || inside === "") {
    throw new Error(`Not a PNG or JPEG inside design/assets/showcase: ${path}`);
  }
  return file;
}

/**
 * Opens a shot's render hash at its pixel size and screenshots it, returning
 * the image. With `out` it also writes the file. The format is `format`, or
 * else whatever `out`'s extension names, or PNG.
 *
 * @param {{ origin: string, hash: string, width: number, height: number,
 *   scale?: number, out?: string, format?: "jpg" | "png",
 *   browser?: import("@playwright/test").Browser }} options
 * @returns {Promise<Buffer>}
 */
export async function renderShot({ origin, hash, width, height, scale = 2, out, format, browser }) {
  const owned = !browser;
  const active = browser ?? (await chromium.launch());
  try {
    const page = await active.newPage({ viewport: { width, height }, deviceScaleFactor: scale });
    /** @type {Error[]} */
    const errors = [];
    page.on("pageerror", (error) => errors.push(error));
    await page.goto(new URL(`/${hash}`, origin).href);
    await page.waitForSelector("body[data-showcase-ready]", { timeout: 30_000 });
    if (errors.length) throw errors[0];
    if (out) await mkdir(dirname(out), { recursive: true });
    const jpeg = (format ?? (out?.endsWith(".jpg") ? "jpg" : "png")) === "jpg";
    const image = await page
      .locator(".shot-canvas")
      .screenshot({ path: out, type: jpeg ? "jpeg" : "png", quality: jpeg ? 92 : undefined });
    await page.close();
    return image;
  } finally {
    if (owned) await active.close();
  }
}

/**
 * A path for messages, relative to the repo root.
 * @param {string} file
 */
export function displayPath(file) {
  return relative(join(assetsDir, "../../.."), file);
}
