import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { showcaseExport } from "./scripts/showcase/plugin.mjs";

export default defineConfig({
  plugins: [svelte(), showcaseExport()],
  resolve: {
    alias: {
      "@lib": new URL("./src/lib", import.meta.url).pathname,
      "@gallery": new URL("./src/gallery", import.meta.url).pathname,
    },
  },
});
