import adapter from "@sveltejs/adapter-node";
import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig, searchForWorkspaceRoot } from "vite";

export default defineConfig({
  plugins: [
    sveltekit({
      adapter: adapter(),
      ...(process.env.PORTAL_BUILD_VERSION && {
        version: { name: process.env.PORTAL_BUILD_VERSION },
      }),
    }),
  ],
  server: { fs: { allow: [searchForWorkspaceRoot(process.cwd())] } },
  optimizeDeps: { exclude: ["@eigin/ui"] },
  ssr: { noExternal: ["@eigin/ui"] },
  resolve: { dedupe: ["svelte"] },
});
