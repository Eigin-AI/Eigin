import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/tests/model-catalog.html");
  await page.waitForFunction(() => typeof window.catalogTests === "object");
});

test("public catalog returns records, enums, optionals and bigint limits through WASM", async ({
  page,
}) => {
  // Catalog data must be embedded; initialization only needs the WASM binary.
  await page.route("**/*.toml", (route) => route.abort());
  const result = await page.evaluate(() => window.catalogTests.values());
  expect(result).toEqual({
    metadataRoundTrips: true,
    familyIsExported: true,
    integerLimit: true,
    unknown: true,
    exactVersion: true,
    unicodeVersion: "一",
    alias: true,
    optionalControl: true,
    rank: true,
    unknownRank: true,
  });
});

test("public catalog operations run in the browser without host services", async ({
  page,
}) => {
  const { offered, ...result } = await page.evaluate(() =>
    window.catalogTests.operations(),
  );
  expect(result).toEqual({
    known: [offered],
    best: offered,
    empty: true,
    effort: true,
    absentEffort: true,
    absentControl: true,
    imageDefaults: true,
    imageOverflow: true,
    signedDimensions: true,
    prices: true,
  });
});
