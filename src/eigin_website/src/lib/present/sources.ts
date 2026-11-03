import { unzip } from "fflate";

export const MAX_INPUT = 64 * 1024 * 1024;
const MAX_EXPANDED = 256 * 1024 * 1024;
const MAX_FILES = 2000;
const media = /\.(png|jpe?g|gif|svg|webp|avif|mp4|webm|mov|m4v|pdf)$/i;

/** Content transferred into the isolated presentation frame. */
export interface Deck {
  markdown: string;
  assets: [string, Blob][];
  baseUrl?: string;
}

/** Fetch a bounded, credential-free deck source. */
export async function fetchSource(input: string, signal?: AbortSignal): Promise<Blob> {
  const url = new URL(input, location.href);
  if (!/^https?:$/.test(url.protocol)) throw new Error("Use an HTTP or HTTPS deck URL.");
  url.searchParams.set("_hot", String(Date.now()));
  const deadline = AbortSignal.timeout(20000);
  const response = await fetch(url, {
    credentials: "omit",
    cache: "no-store",
    signal: signal ? AbortSignal.any([signal, deadline]) : deadline,
  });
  if (!response.ok) throw new Error(`Could not load deck (HTTP ${response.status}).`);
  const reader = response.body?.getReader();
  if (!reader) throw new Error("The deck response is empty.");
  const chunks: Uint8Array<ArrayBuffer>[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_INPUT) throw new Error("Deck exceeds the 64 MiB input limit.");
      chunks.push(value as Uint8Array<ArrayBuffer>);
    }
  } finally {
    await reader.cancel();
  }
  return new Blob(chunks);
}

function mime(path: string): string {
  const types: Record<string, string> = {
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    svg: "image/svg+xml",
    webp: "image/webp",
    avif: "image/avif",
    mp4: "video/mp4",
    webm: "video/webm",
    mov: "video/quicktime",
    m4v: "video/x-m4v",
    pdf: "application/pdf",
  };
  return types[path.split(".").pop()!.toLowerCase()] ?? "application/octet-stream";
}

/** Select a deck with the legacy filename preference. */
export function deckPath(paths: string[]): string {
  const path =
    paths.find((p) => p.toLowerCase() === "deck.md") ??
    paths.find((p) => /(^|\/)deck\.md$/i.test(p)) ??
    paths.find((p) => /\.md$/i.test(p));
  if (!path) throw new Error("No .md deck found. Include deck.md in your folder or ZIP.");
  return path;
}

/** Decode ZIPs asynchronously, with limits checked before decompression. */
export async function loadZip(file: Blob): Promise<Deck> {
  if (file.size > MAX_INPUT) throw new Error("ZIP exceeds the 64 MiB input limit.");
  const bytes = new Uint8Array(await file.arrayBuffer());
  let total = 0;
  let count = 0;
  let rejected = false;
  const entries = await new Promise<Record<string, Uint8Array<ArrayBuffer>>>((resolve, reject) => {
    unzip(
      bytes,
      {
        filter(entry) {
          count++;
          total += entry.originalSize;
          if (
            count > MAX_FILES ||
            total > MAX_EXPANDED ||
            /(^|\/)\.\.(\/|$)|^[/\\]|\\/.test(entry.name)
          )
            rejected = true;
          return !rejected && !/(^|\/)__MACOSX\//.test(entry.name);
        },
      },
      (error, files) => {
        if (rejected)
          reject(
            new Error("ZIP exceeds 2,000 files / 256 MiB expanded, or contains unsafe paths."),
          );
        else if (error) reject(new Error("Could not read ZIP: " + error.message));
        else resolve(files as Record<string, Uint8Array<ArrayBuffer>>);
      },
    );
  });
  const paths = Object.keys(entries).filter((p) => !p.endsWith("/"));
  const path = deckPath(paths);
  const prefix = path.replace(/[^/]*$/, "");
  return {
    markdown: new TextDecoder().decode(entries[path]),
    assets: paths
      .filter((p) => p.startsWith(prefix) && media.test(p))
      .map((p) => [
        p.slice(prefix.length).toLowerCase(),
        new Blob([entries[p]], { type: mime(p) }),
      ]),
  };
}

/** Load a local ZIP or standalone Markdown file without uploading it. */
export async function loadFile(file: File): Promise<Deck> {
  if (/\.zip$/i.test(file.name)) return loadZip(file);
  if (!/\.(md|markdown|txt)$/i.test(file.name)) throw new Error("Choose a ZIP or Markdown file.");
  if (file.size > MAX_INPUT) throw new Error("Deck exceeds the 64 MiB input limit.");
  return { markdown: await file.text(), assets: [] };
}

export interface Directory extends FileSystemDirectoryHandle {
  queryPermission(options: { mode: "read" }): Promise<PermissionState>;
  requestPermission(options: { mode: "read" }): Promise<PermissionState>;
}

/** Read a directory snapshot, resolving media beside its selected Markdown file. */
export async function loadFolder(directory: Directory): Promise<Deck> {
  const files = new Map<string, File>();
  let size = 0;
  async function walk(dir: Directory, prefix = "", depth = 0): Promise<void> {
    if (depth > 32) throw new Error("Folder nesting exceeds 32 levels.");
    for await (const entry of dir.values()) {
      const path = prefix + entry.name;
      if (entry.kind === "directory") await walk(entry as Directory, path + "/", depth + 1);
      else {
        const file = await entry.getFile();
        size += file.size;
        if (files.size >= MAX_FILES || size > MAX_EXPANDED)
          throw new Error("Folder exceeds 2,000 files / 256 MiB.");
        files.set(path, file);
      }
    }
  }
  await walk(directory);
  const path = deckPath([...files.keys()]);
  const markdown = files.get(path)!;
  if (markdown.size > MAX_INPUT) throw new Error("Deck exceeds the 64 MiB input limit.");
  const prefix = path.replace(/[^/]*$/, "");
  return {
    markdown: await markdown.text(),
    assets: [...files]
      .filter(([p]) => p.startsWith(prefix) && media.test(p))
      .map(([p, f]) => [p.slice(prefix.length).toLowerCase(), f]),
  };
}
