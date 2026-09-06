import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte()],
  resolve: {
    alias: {
      "@lib": new URL("./src/lib", import.meta.url).pathname,
      "@gallery": new URL("./src/gallery", import.meta.url).pathname,
    },
  },
});
