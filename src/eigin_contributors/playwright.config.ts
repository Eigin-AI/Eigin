import { randomBytes } from "node:crypto";
import { testDatabaseUrl } from "./tests/database.ts";
import { defineConfig, devices } from "@playwright/test";
process.env.PUBLICATION_TEST_RUN ??= randomBytes(8).toString("hex");
const databaseUrl = testDatabaseUrl();
export default defineConfig({
  testDir: "tests",
  workers: 2,
  globalTeardown: "./tests/teardown.ts",
  testMatch: "**/*.spec.ts",
  use: { baseURL: "http://localhost:5276", trace: "retain-on-failure" },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["Pixel 7"] } },
  ],
  webServer: {
    command: "node tests/server.ts",
    reuseExistingServer: false,
    gracefulShutdown: { signal: "SIGTERM", timeout: 5000 },
    env: {
      TEST_DATABASE_URL: databaseUrl,
      PUBLICATION_TEST_RUN: process.env.PUBLICATION_TEST_RUN,
      ORIGIN: "http://localhost:5276",
      GITLAB_CLIENT_ID: "browser-test",
      GITLAB_CLIENT_SECRET: "browser-test",
      REVIEWER_GITLAB_IDS:
        "700000000001,700000000002,700000000003,700000000004,700000000005,700000000006",
    },
    url: "http://localhost:5276",
  },
});
