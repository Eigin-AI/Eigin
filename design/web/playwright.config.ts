import { defineConfig, devices } from "@playwright/test";

/* Overridable so a second worktree can test beside a gallery already running. */
const port = Number(process.env.GALLERY_PORT ?? 5173);

export default defineConfig({
  testDir: "tests",
  // Keep output terse — this is an agent-facing check, not a QA suite.
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: `http://localhost:${port}`,
    trace: "on-first-retry",
  },
  /* Two engines: WebKit catches the Safari-only layout and animation bugs
     these components will meet in the wild. Playwright ships its own WebKit,
     so no Safari install is needed — but it supports macOS and Linux only. */
  projects: [
    { name: "chromium", use: devices["Desktop Chrome"] },
    { name: "webkit", use: devices["Desktop Safari"] },
  ],
  webServer: {
    command: `npm run dev -- --port ${port} --strictPort`,
    url: `http://localhost:${port}`,
    reuseExistingServer: true,
    timeout: 60_000,
  },
});
