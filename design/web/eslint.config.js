import globals from "globals";
import js from "@eslint/js";
import svelte from "eslint-plugin-svelte";
import ts from "typescript-eslint";

export default ts.config(
  {
    ignores: [
      "node_modules/",
      "dist/",
      "src/lib/generated/",
      "test-results/",
      "playwright-report/",
    ],
  },
  js.configs.recommended,
  ...ts.configs.recommended,
  ...svelte.configs.recommended,
  {
    // The gallery uses plain Vite; SvelteKit is a sibling workspace dependency.
    rules: { "svelte/no-navigation-without-resolve": "off" },
  },
  {
    files: ["**/*.svelte"],
    languageOptions: {
      parserOptions: {
        parser: ts.parser,
        projectService: true,
        extraFileExtensions: [".svelte"],
      },
    },
  },
  {
    files: ["**/*.ts", "**/*.svelte"],
    languageOptions: {
      globals: { ...globals.browser },
      parserOptions: {
        projectService: true,
      },
    },
  },
  {
    files: ["**/*.svelte", "**/*.ts"],
    ignores: ["playwright.config.ts"],
  },
  {
    /* Runic modules: Svelte's runes compiled into plain TS. */
    files: ["**/*.svelte.ts"],
    languageOptions: {
      parser: svelte.parser,
      parserOptions: {
        parser: ts.parser,
        projectService: true,
        extraFileExtensions: [".svelte"],
      },
    },
  },
  {
    /* The class check runs under plain node, outside the browser globals. */
    files: ["scripts/**/*.mjs"],
    languageOptions: {
      globals: { ...globals.node },
    },
  },
);
