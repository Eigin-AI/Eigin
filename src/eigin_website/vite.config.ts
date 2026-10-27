import adapter from "@sveltejs/adapter-static";
import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig, searchForWorkspaceRoot } from "vite";

export default defineConfig({
  plugins: [sveltekit({ adapter: adapter() })],
  server: { fs: { allow: [searchForWorkspaceRoot(process.cwd())] } },
  optimizeDeps: { exclude: ["@eigin/ui"] },
  ssr: { noExternal: ["@eigin/ui"] },
  resolve: { dedupe: ["svelte"] },
});
