import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "tests",
  // Keep output terse — this is an agent-facing check, not a QA suite.
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: "http://localhost:5173",
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
    command: "npm run dev -- --port 5173 --strictPort",
    url: "http://localhost:5173",
    reuseExistingServer: true,
    timeout: 60_000,
  },
});
