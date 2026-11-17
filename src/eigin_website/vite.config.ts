import { readdirSync } from "node:fs";
import { newsHeadings } from "./tools/news-headings.ts";
import { newsMetadata } from "./tools/news-metadata.ts";
import { mdsvex } from "mdsvex";
import adapter from "@sveltejs/adapter-static";
import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig, searchForWorkspaceRoot } from "vite";

export default defineConfig({
  plugins: [
    newsMetadata(),
    sveltekit({
      adapter: adapter(),
      extensions: [".svelte", ".svx"],
      preprocess: mdsvex({ remarkPlugins: [newsHeadings] }),
      prerender: {
        handleUnseenRoutes: ({ routes, message }) => {
          // An empty catalogue has no article URLs to prerender.
          const empty = !readdirSync(new URL("./src/lib/content/news/posts/", import.meta.url), {
            recursive: true,
          }).some((file) => String(file).endsWith(".svx"));
          if (empty && routes.every((route) => route === "/[lang]/news/[slug]")) return;
          throw new Error(message);
        },
      },
    }),
  ],
  server: { fs: { allow: [searchForWorkspaceRoot(process.cwd())] } },
  optimizeDeps: { exclude: ["@eigin/ui"] },
  ssr: { noExternal: ["@eigin/ui"] },
  resolve: {
    dedupe: ["svelte"],
  },
});
