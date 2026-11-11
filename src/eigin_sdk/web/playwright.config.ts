import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "tests",
  reporter: "list",
  use: { baseURL: "http://localhost:5276" },
  projects: [
    { name: "chromium", use: { browserName: "chromium" } },
    { name: "firefox", use: { browserName: "firefox" } },
    { name: "webkit", use: { browserName: "webkit" } },
  ],
  webServer: [
    {
      command: "vite --port 5276 --strictPort",
      url: "http://localhost:5276/tests/index.html",
      reuseExistingServer: false,
    },
  ],
});
