import { readFile } from "node:fs/promises";
import { compile } from "mdsvex";
import type { Plugin } from "vite";

/** Extract frontmatter without importing article components into navigation bundles. */
export function newsMetadata(): Plugin {
  const query = "?news-metadata";
  const prefix = "\0news-metadata:";
  return {
    name: "news-metadata",
    enforce: "pre",
    async resolveId(source, importer) {
      if (!source.endsWith(query)) return;
      const resolved = await this.resolve(source.slice(0, -query.length), importer, {
        skipSelf: true,
      });
      if (resolved) return prefix + resolved.id + ".js";
    },
    async load(id) {
      if (!id.startsWith(prefix)) return;
      const file = id.slice(prefix.length, -3);
      this.addWatchFile(file);
      const result = await compile(await readFile(file, "utf8"), { filename: file });
      return `export default ${JSON.stringify(result?.data?.fm ?? {})};`;
    },
  };
}
