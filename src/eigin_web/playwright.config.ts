import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "tests",
  reporter: "list",
  use: { baseURL: "http://localhost:5275" },
  projects: [
    { name: "chromium", use: { browserName: "chromium" } },
    { name: "firefox", use: { browserName: "firefox" } },
    { name: "webkit", use: { browserName: "webkit" } },
  ],
  webServer: {
    command: "npm run preview -- --port 5275 --strictPort",
    url: "http://localhost:5275",
    reuseExistingServer: false,
  },
});
