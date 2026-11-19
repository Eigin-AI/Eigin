import { mkdir, writeFile, rm } from "node:fs/promises";
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { testDatabaseUrl } from "./database.ts";

const run = process.env.PUBLICATION_TEST_RUN;
if (!run || !/^[a-f0-9]{16}$/.test(run))
  throw new Error("PUBLICATION_TEST_RUN is required");
const created: URL[] = [];
let child: ReturnType<typeof spawn> | undefined;
try {
  // Call discovery runs when Vite starts, before Playwright's global setup.
  for (const project of ["desktop", "mobile", "open"]) {
    const slug = `publication-test-${run}-${project}`;
    const directory = new URL(`../content/calls/${slug}/`, import.meta.url);
    await mkdir(directory);
    created.push(directory);
    await writeFile(
      new URL("call.json", directory),
      JSON.stringify({
        slug,
        title:
          project === "open"
            ? "Open fixture call"
            : `Publication test ${project}`,
        summary: "Synthetic browser test call.",
        publicListing: true,
        opensAt:
          project === "open"
            ? new Date(Date.now() - 3600_000).toISOString()
            : "2020-01-01T00:00:00Z",
        closesAt:
          project === "open"
            ? new Date(Date.now() + 3600_000).toISOString()
            : "2020-02-01T00:00:00Z",
        selectedAmountMinor: 50000,
        runnerUpAmountMinor: 25000,
        currency: "EUR",
        displayTimezone: "Europe/Copenhagen",
      }),
    );
    await writeFile(
      new URL("brief.md", directory),
      "# Synthetic call\n\nPublic brief for publication browser tests.\n",
    );
  }
  child = spawn(
    process.execPath,
    [
      new URL(
        "./bin/vite.js",
        "file://" + createRequire(import.meta.url).resolve("vite/package.json"),
      ).pathname,
      "--port",
      "5276",
      "--strictPort",
    ],
    {
      stdio: "inherit",
      env: { ...process.env, DATABASE_URL: testDatabaseUrl() },
    },
  );
  const stop = () => child?.kill("SIGTERM");
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  process.exitCode = await new Promise<number>((resolve, reject) => {
    child!.once("error", reject);
    child!.once("exit", (code) => resolve(code ?? 0));
  });
  process.off("SIGINT", stop);
  process.off("SIGTERM", stop);
} finally {
  for (const directory of created)
    await rm(directory, { recursive: true, force: true });
}
