import { rm } from "node:fs/promises";

/** Remove only this Playwright run's configured call fixtures. */
export default async function teardown() {
  const run = process.env.PUBLICATION_TEST_RUN;
  if (!run || !/^[a-f0-9]{16}$/.test(run))
    throw new Error("Missing fixture run ID");
  for (const project of ["desktop", "mobile", "open"]) {
    await rm(
      new URL(
        `../content/calls/publication-test-${run}-${project}/`,
        import.meta.url,
      ),
      { recursive: true, force: true },
    );
  }
}
