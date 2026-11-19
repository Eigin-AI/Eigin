import { testDatabaseUrl } from "./database.ts";
import { test, expect } from "@playwright/test";
import { randomBytes } from "node:crypto";
import { createPool } from "../src/lib/server/database.ts";
import { digest } from "../src/lib/server/submissions.ts";

for (const javaScriptEnabled of [false, true]) {
  test.describe(javaScriptEnabled ? "hydrated" : "without JavaScript", () => {
    test.use({ javaScriptEnabled });
    test("reviewers privately select exact revisions with saved results, pagination and one confirmation", async ({
      page,
      context,
      browser,
    }, info) => {
      // This workflow seeds 51 entries and exercises multiple native page submissions.
      test.setTimeout(60_000);
      const pool = createPool(testDatabaseUrl());
      const marker = randomBytes(8).toString("hex");
      const slug = `selection-${marker}`;
      const base = `/review/calls/${slug}/selection`;
      const origin = "http://localhost:5276";
      const token = randomBytes(32).toString("base64url");
      const reviewerId =
        info.project.name === "desktop" ? 700000000003 : 700000000004;
      const ids: string[] = [];
      let sessionUser = "";
      const outsider = await browser.newContext({ baseURL: origin });
      const count = async (table: string) =>
        Number(
          (
            await pool.query(
              `SELECT count(*) FROM ${table} WHERE call_slug=$1`,
              [slug],
            )
          ).rows[0].count,
        );
      try {
        sessionUser = (
          await pool.query(
            "INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES ($1,$2,'Selection reviewer') RETURNING id",
            [reviewerId, `selection-${marker}`],
          )
        ).rows[0].id;
        ids.push(sessionUser);
        await pool.query(
          "INSERT INTO sessions VALUES ($1,$2,clock_timestamp()+interval '1 hour')",
          [digest(token), sessionUser],
        );
        await context.addCookies([
          {
            name: "contributors_session",
            value: token,
            url: origin,
            httpOnly: true,
            sameSite: "Lax",
          },
        ]);
        const contract = {
          slug,
          opensAt: "2020-01-01T00:00:00Z",
          closesAt: "2020-02-01T00:00:00Z",
          selectedAmountMinor: 50000,
          runnerUpAmountMinor: 25000,
          currency: "EUR",
          mode: "rehearsal",
        };
        await pool.query("INSERT INTO call_contracts VALUES ($1,$2,$3)", [
          slug,
          digest(JSON.stringify(contract)),
          JSON.stringify(contract),
        ]);
        await pool.query(
          "INSERT INTO agreement_snapshots VALUES ($1,'test',$2)",
          [digest(marker), marker],
        );
        for (let i = 0; i < 51; i++) {
          const id = (
            await pool.query(
              "INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES ($1,$2,$3) RETURNING id",
              [
                8200000000000000 + Math.floor(Math.random() * 1000000000000),
                `selection-author-${marker}-${i}`,
                `Author ${i}`,
              ],
            )
          ).rows[0].id;
          ids.push(id);
          const submission = (
            await pool.query(
              "INSERT INTO submissions(call_slug,user_id) VALUES ($1,$2) RETURNING id",
              [slug, id],
            )
          ).rows[0].id;
          const markdown = `# Proposal ${i}\n\nPrivate selection fixture.`;
          const revision = (
            await pool.query(
              `INSERT INTO submission_revisions
        (submission_id,markdown,filename,sha256,received_at,contact_email,author_name,author_email,cla_sha256,terms_sha256,consent)
        VALUES ($1,$2,'spec.md',$3,clock_timestamp(),'contact@example.org',$4,'git@example.org',$5,$5,'{}') RETURNING id`,
              [
                submission,
                markdown,
                digest(markdown),
                `Author ${i}`,
                digest(marker),
              ],
            )
          ).rows[0].id;
          await pool.query(
            "UPDATE submissions SET current_revision_id=$1 WHERE id=$2",
            [revision, submission],
          );
        }
        for (const path of [
          base,
          base + "/selected",
          base + "/selected/download",
        ]) {
          expect((await outsider.request.get(path)).status()).toBe(404);
        }
        expect(
          (
            await outsider.request.post(base + "?/confirm", {
              headers: { Origin: origin },
              form: { confirmationText: "confirm" },
            })
          ).status(),
        ).toBe(404);
        await page.goto(`/review/calls/${slug}`);
        await expect(page.locator(".review-list .review-entry")).toHaveCount(
          50,
        );
        await expect(page.locator(".review-count")).toHaveText("51");
        if (javaScriptEnabled) {
          await page.evaluate(() => document.fonts.ready.then(() => {}));
          await page.screenshot({
            path: `/tmp/review-list-51-${info.project.name}.png`,
            fullPage: true,
          });
        }
        await expect(page.locator(".review-list")).not.toContainText(
          "Revision",
        );
        const listSize = await page.locator(".review-list").evaluate((el) => ({
          height: el.clientHeight,
          content: el.scrollHeight,
        }));
        expect(listSize.content).toBeGreaterThan(listSize.height);
        expect(listSize.height).toBeLessThan(page.viewportSize()!.height);
        const row = await page.locator(".review-entry").first().boundingBox();
        expect(row!.height).toBeLessThan(110);
        await page
          .getByRole("navigation", { name: "Submission pages" })
          .getByRole("link", { name: "Next", exact: true })
          .click();
        await expect(page.locator(".review-list .review-entry")).toHaveCount(1);
        await page.locator(".review-entry").click();
        await expect(
          page.getByRole("heading", { name: "Proposal 0", exact: true }),
        ).toBeVisible();
        await expect(page.locator(".review-list .review-entry")).toHaveCount(1);
        await page
          .getByRole("navigation", { name: "Submission pages" })
          .getByRole("link", { name: "Previous", exact: true })
          .click();
        await expect(page.locator(".review-list .review-entry")).toHaveCount(
          50,
        );
        await page
          .getByRole("link", { name: "Choose recipients", exact: true })
          .click();
        await expect(
          page.getByRole("heading", {
            name: "Choose recipients",
            exact: true,
            level: 1,
          }),
        ).toBeVisible();
        await expect(page.locator(".review-toolbar")).toHaveCount(0);
        await expect(page.locator(".selection-list")).not.toContainText(
          "Revision",
        );
        const pickerHeights = await page
          .locator(".decision-actions .eigin-btn")
          .evaluateAll((elements) =>
            elements.map((el) => el.getBoundingClientRect().height),
          );
        expect(
          Math.max(...pickerHeights) - Math.min(...pickerHeights),
        ).toBeLessThanOrEqual(1);
        await page
          .getByRole("group", { name: "Author 50 · Proposal 50", exact: true })
          .getByLabel("Selected spec", { exact: true })
          .check();
        if (javaScriptEnabled) {
          // Native forms work before hydration; mutual radio clearing requires the enhancement.
          await expect(page.locator("[data-enhanced]")).toHaveAttribute(
            "data-enhanced",
            "true",
          );
          const first = page.getByRole("group", {
            name: "Author 50 · Proposal 50",
            exact: true,
          });
          await first.getByLabel("Runner-up spec", { exact: true }).check();
          await expect(
            first.getByLabel("Selected spec", { exact: true }),
          ).not.toBeChecked();
          await first.getByLabel("Selected spec", { exact: true }).check();
          await expect(
            first.getByLabel("Runner-up spec", { exact: true }),
          ).not.toBeChecked();
          await page.evaluate(() => document.fonts.ready.then(() => {}));
          await page.screenshot({
            path: `/tmp/recipient-picker-${info.project.name}.png`,
            fullPage: true,
          });
        }
        await page.getByRole("button", { name: "Next", exact: true }).click();
        await page
          .getByRole("group", { name: "Author 0 · Proposal 0", exact: true })
          .getByLabel("Runner-up spec", { exact: true })
          .check();
        await page
          .getByRole("button", { name: "Previous", exact: true })
          .click();
        await page
          .getByRole("group", { name: "Author 49 · Proposal 49", exact: true })
          .getByLabel("Selected spec", { exact: true })
          .check();
        await page.getByRole("button", { name: "Next", exact: true }).click();
        await page
          .getByRole("button", { name: "Previous", exact: true })
          .click();
        await page
          .getByRole("button", { name: "Write the results", exact: true })
          .click();
        await expect(
          page.getByRole("heading", {
            name: "Write the results",
            exact: true,
            level: 1,
          }),
        ).toBeVisible();
        await expect(page.locator(".selection-summary")).toContainText(
          "Author 49",
        );
        await expect(page.locator(".selection-summary")).toContainText(
          "Author 0",
        );
        await expect(page.locator(".selection-summary")).toContainText("€500");
        await expect(page.locator(".selection-summary")).toContainText("€250");
        await expect(page.locator(".selection-summary")).not.toContainText(
          "Revision",
        );
        const editorHeights = await page
          .locator(".editor-actions .eigin-btn")
          .evaluateAll((elements) =>
            elements.map((el) => el.getBoundingClientRect().height),
          );
        expect(
          Math.max(...editorHeights) - Math.min(...editorHeights),
        ).toBeLessThanOrEqual(1);
        expect(await count("call_selections")).toBe(0);
        expect(await count("selection_confirmations")).toBe(0);
        await expect(page.locator("textarea[placeholder]")).toHaveCount(4);
        for (const field of await page.locator("textarea").all()) {
          await expect(field).toHaveValue("");
          expect(
            (await field.getAttribute("placeholder"))!.length,
          ).toBeGreaterThan(30);
        }
        if (javaScriptEnabled) {
          await page.evaluate(() => document.fonts.ready.then(() => {}));
          await page.screenshot({
            path: `/tmp/results-editor-${info.project.name}.png`,
            fullPage: true,
          });
        }
        const copy = {
          introduction: "Two complementary approaches to safer tools.",
          selectedSummary: "A small deterministic rules engine.",
          runnerUpSummary: "A compact multilingual classifier.",
          learned:
            "We learned to preserve approval when uncertain.\n\nThank you to everyone who contributed.",
        };
        await page
          .locator('textarea[name="introduction"]')
          .fill(copy.introduction);
        await page
          .getByRole("button", { name: "Save draft", exact: true })
          .click();
        await expect(page.getByRole("status")).toContainText("Draft saved");
        expect(await count("selection_drafts")).toBe(1);
        expect(await count("call_selections")).toBe(0);
        await page.goto(`/review/calls/${slug}`);
        await page
          .getByRole("link", { name: "Continue results", exact: true })
          .click();
        await expect(
          page.getByRole("heading", { name: "Write the results", level: 1 }),
        ).toBeVisible();
        await page
          .getByRole("link", { name: "Change recipients", exact: true })
          .click();
        await expect(
          page.getByRole("heading", { name: "Choose recipients", level: 1 }),
        ).toBeVisible();
        await page.getByRole("link", { name: "Cancel", exact: true }).click();
        await expect(
          page.getByRole("heading", { name: "Write the results", level: 1 }),
        ).toBeVisible();
        const literalText =
          '\n</textarea><img src="/missing-review-test" onerror="window.resultsInjected=true"> & "quotes"';
        await page.locator('textarea[name="learned"]').fill(literalText);
        await page
          .getByRole("button", { name: "Save draft", exact: true })
          .click();
        await expect(page.getByRole("status")).toContainText("Draft saved");
        await page.reload();
        await expect(page.locator('textarea[name="learned"]')).toHaveValue(
          literalText,
        );
        await expect(page.locator(".results-editor img")).toHaveCount(0);
        expect(await page.evaluate(() => "resultsInjected" in window)).toBe(
          false,
        );
        await expect(page.locator('textarea[name="introduction"]')).toHaveValue(
          copy.introduction,
        );
        for (const [key, value] of Object.entries(copy))
          await page.locator(`textarea[name="${key}"]`).fill(value);
        const draftVersion = await page
          .locator('input[name="draftVersion"]')
          .inputValue();
        const selectedValue = await page
          .locator('input[name="selected"]')
          .inputValue();
        const runnerValue = await page
          .locator('input[name="runnerUp"]')
          .inputValue();
        expect(
          (
            await page.request.post(base + "?/saveDraft", {
              headers: { Origin: origin },
              form: {
                ...copy,
                introduction: "Another tab's saved introduction.",
                draftVersion,
                selected: selectedValue,
                runnerUp: runnerValue,
              },
            })
          ).status(),
        ).toBe(200);
        await page
          .getByRole("button", { name: "Save draft", exact: true })
          .click();
        await expect(page.getByRole("alert")).toContainText("draft changed");
        await expect(page.locator('textarea[name="introduction"]')).toHaveValue(
          copy.introduction,
        );
        await page
          .getByRole("link", { name: "Reload saved draft", exact: true })
          .click();
        await expect(page.locator('textarea[name="introduction"]')).toHaveValue(
          "Another tab's saved introduction.",
        );
        await page
          .locator('textarea[name="introduction"]')
          .fill(copy.introduction);
        await page
          .getByRole("button", { name: "Preview results", exact: true })
          .click();
        await expect(
          page.getByRole("heading", {
            name: "Preview the results",
            exact: true,
            level: 1,
          }),
        ).toBeVisible();
        await expect(page.locator(".results-page")).toContainText(
          copy.selectedSummary,
        );
        await expect(page.locator(".results-page")).toContainText(
          copy.runnerUpSummary,
        );
        await expect(
          page.getByRole("heading", { name: "What we learned", exact: true }),
        ).toBeVisible();
        expect(await count("call_selections")).toBe(0);
        expect(await count("selection_confirmations")).toBe(1);
        await expect(page.locator(".results-page")).not.toContainText(
          "Why it matters",
        );
        for (const card of await page
          .locator(".results-page .selected-spec-card")
          .all()) {
          const spacing = await card.evaluate((element) => {
            const author = element.querySelector(".selected-author h4")!;
            const title = element.querySelector(".selected-author h5")!;
            const description = element.querySelector(".spec-description")!;
            return {
              authorGap:
                title.getBoundingClientRect().top -
                author.getBoundingClientRect().bottom,
              descriptionGap:
                description.getBoundingClientRect().top -
                title.getBoundingClientRect().bottom,
              margin: getComputedStyle(title).marginBottom,
            };
          });
          expect(spacing.margin).toBe("0px");
          expect(spacing.authorGap).toBeGreaterThanOrEqual(15);
          expect(spacing.authorGap).toBeLessThanOrEqual(17);
          expect(spacing.descriptionGap).toBeGreaterThanOrEqual(31);
          expect(spacing.descriptionGap).toBeLessThanOrEqual(33);
        }
        await expect(page.locator(".review-toolbar")).toHaveCount(0);
        const abandonedToken = await page
          .locator('input[name="confirmationToken"]')
          .inputValue();
        await page
          .getByRole("button", { name: "Edit results", exact: true })
          .click();
        expect(await count("selection_confirmations")).toBe(0);
        expect(
          (
            await page.request.post(base + "?/confirm", {
              headers: { Origin: origin },
              form: {
                confirmationToken: abandonedToken,
                confirmationText: "confirm",
              },
            })
          ).status(),
        ).toBe(409);
        await expect(
          page.locator('textarea[name="selectedSummary"]'),
        ).toHaveValue(copy.selectedSummary);
        await page
          .getByRole("button", { name: "Preview results", exact: true })
          .click();
        const confirmationToken = await page
          .locator('input[name="confirmationToken"]')
          .inputValue();
        if (javaScriptEnabled)
          await page.evaluate(() => document.fonts.ready.then(() => {}));
        if (javaScriptEnabled)
          await page.screenshot({
            path: `/tmp/results-preview-${info.project.name}.png`,
            fullPage: true,
          });
        expect(
          (
            await page.request.post(base + "?/confirm", {
              headers: { Origin: "https://evil.example" },
              form: { confirmationToken, confirmationText: "confirm" },
            })
          ).status(),
        ).toBe(403);
        expect(
          (
            await page.request.post(base + "?/confirm", {
              headers: { Origin: origin },
              form: { confirmationToken, confirmationText: "wrong" },
            })
          ).status(),
        ).toBe(400);
        expect(await count("call_selections")).toBe(0);
        await page
          .getByRole("button", {
            name: "Confirm selection",
            exact: true,
          })
          .click();
        expect(await count("call_selections")).toBe(0);
        await page.getByLabel("Type confirm to confirm").fill("confirm");
        await page
          .getByRole("button", {
            name: "Confirm selection",
            exact: true,
          })
          .click();
        await expect(
          page.getByRole("heading", {
            name: "Selection confirmed",
            exact: true,
          }),
        ).toBeVisible();
        expect(await count("call_selections")).toBe(1);
        expect(await count("selection_confirmations")).toBe(0);
        await expect(
          page.getByRole("button", {
            name: "Confirm selection",
            exact: true,
          }),
        ).toHaveCount(0);
        expect(
          (
            await page.request.post(base + "?/confirm", {
              headers: { Origin: origin },
              form: { confirmationToken, confirmationText: "confirm" },
            })
          ).status(),
        ).toBe(200);
        expect(await count("call_selections")).toBe(1);
        await page.goto(base + "/selected");
        await expect(
          page.getByRole("heading", { name: "Proposal 49", exact: true }),
        ).toBeVisible();
        const download = await page.request.get(base + "/selected/download");
        expect(await download.text()).toContain("# Proposal 49");
        expect(download.headers()["cache-control"]).toBe("no-store");
        expect(
          (await outsider.request.get(base + "/selected/download")).status(),
        ).toBe(404);
        expect((await page.request.get(`/calls/${slug}`)).status()).toBe(404);
        await page.goto("/calls/tool-safety");
        await expect(
          page.getByText("Selection confirmed", { exact: true }),
        ).toHaveCount(0);
        await page.goto("/review/calls/tool-safety");
        await expect(
          page.getByRole("link", { name: "Choose recipients", exact: true }),
        ).toHaveCount(0);
        await page.goto(base);
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth,
          ),
        ).toBe(true);
      } finally {
        await outsider.close().catch(() => {});
        await pool.query(
          "DELETE FROM selection_confirmations WHERE call_slug=$1",
          [slug],
        );
        await pool.query("DELETE FROM selection_drafts WHERE call_slug=$1", [
          slug,
        ]);
        await pool.query("DELETE FROM call_selections WHERE call_slug=$1", [
          slug,
        ]);
        await pool.query(
          "DELETE FROM sessions WHERE user_id=ANY($1::bigint[])",
          [ids],
        );
        await pool.query(
          "UPDATE submissions SET current_revision_id=NULL WHERE call_slug=$1",
          [slug],
        );
        await pool.query(
          "DELETE FROM submission_revisions WHERE submission_id IN (SELECT id FROM submissions WHERE call_slug=$1)",
          [slug],
        );
        await pool.query("DELETE FROM submissions WHERE call_slug=$1", [slug]);
        await pool.query("DELETE FROM call_contracts WHERE slug=$1", [slug]);
        await pool.query("DELETE FROM agreement_snapshots WHERE sha256=$1", [
          digest(marker),
        ]);
        await pool.query("DELETE FROM users WHERE id=ANY($1::bigint[])", [ids]);
        await pool.end();
      }
    });
  });
}
