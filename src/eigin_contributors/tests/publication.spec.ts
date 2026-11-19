import { testDatabaseUrl } from "./database.ts";
import { test, expect } from "@playwright/test";
import { randomBytes } from "node:crypto";
import { createPool } from "../src/lib/server/database.ts";
import { digest } from "../src/lib/server/submissions.ts";
import { Selection } from "../src/lib/server/selection.ts";

for (const javaScriptEnabled of [false, true]) {
  test.describe(
    javaScriptEnabled ? "hydrated publication" : "native publication",
    () => {
      test.use({ javaScriptEnabled });
      test("closed calls remain forthcoming until explicit publication exposes only the recorded pair", async ({
        page,
        context,
        browser,
      }, info) => {
        if (!process.env.PUBLICATION_TEST_RUN)
          throw new Error(
            "Playwright must supply PUBLICATION_TEST_RUN for its isolated call fixtures.",
          );
        const slug = `publication-test-${process.env.PUBLICATION_TEST_RUN}-${info.project.name}`;
        const origin = "http://localhost:5276";
        const base = `/review/calls/${slug}/selection`;
        const pool = createPool(testDatabaseUrl());
        const ids: string[] = [];
        const marker = randomBytes(8).toString("hex");
        const token = randomBytes(32).toString("base64url");
        const gitlabId =
          info.project.name === "desktop" ? "700000000005" : "700000000006";
        const outsider = await browser.newContext({ baseURL: origin });
        const anonymous = await outsider.newPage();
        try {
          const user = (
            await pool.query(
              `INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES ($1,$2,'Publication reviewer') RETURNING id`,
              [gitlabId, `publication-${marker}`],
            )
          ).rows[0];
          ids.push(user.id);
          const reviewer = {
            id: user.id,
            gitlabId,
            username: `publication-${marker}`,
            name: "Publication reviewer",
          };
          await pool.query(
            "INSERT INTO sessions VALUES ($1,$2,clock_timestamp()+interval '1 hour')",
            [digest(token), user.id],
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
            "INSERT INTO agreement_snapshots VALUES ($1,'synthetic-publication-test',$2)",
            [digest(marker), marker],
          );
          const choices = [];
          for (let i = 0; i < 3; i++) {
            const author = (
              await pool.query(
                "INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES ($1,$2,$3) RETURNING id",
                [
                  8300000000000000 + Math.floor(Math.random() * 1000000000000),
                  `publication-author-${marker}-${i}`,
                  `Public author ${i}`,
                ],
              )
            ).rows[0];
            ids.push(author.id);
            const submission = (
              await pool.query(
                "INSERT INTO submissions(call_slug,user_id) VALUES ($1,$2) RETURNING id",
                [slug, author.id],
              )
            ).rows[0];
            const markdown =
              i === 2
                ? `# Unselected secret ${marker}`
                : `# Funded proposal ${i}\n\nPublished body ${i}.\n\n<script>window.injected=true</script>\n\n![remote](https://example.invalid/pixel)`;
            const revision = (
              await pool.query(
                `INSERT INTO submission_revisions
            (submission_id,markdown,filename,sha256,received_at,contact_email,author_name,author_email,cla_sha256,terms_sha256,consent)
            VALUES ($1,$2,'spec.md',$3,clock_timestamp(),'private-contact@example.invalid',$4,'private-author@example.invalid',$5,$5,$6) RETURNING id`,
                [
                  submission.id,
                  markdown,
                  digest(markdown),
                  `Public author ${i}`,
                  digest(marker),
                  JSON.stringify({
                    synthetic: true,
                    accepted: false,
                    secret: `consent-${marker}`,
                  }),
                ],
              )
            ).rows[0];
            await pool.query(
              "UPDATE submissions SET current_revision_id=$1 WHERE id=$2",
              [revision.id, submission.id],
            );
            choices.push({
              submissionId: submission.id,
              revisionId: revision.id,
            });
          }
          await anonymous.goto("/");
          const card = anonymous.locator("#previous-calls article").filter({
            has: anonymous.getByRole("heading", {
              name: `Publication test ${info.project.name}`,
            }),
          });
          await expect(card).toContainText("Results forthcoming");
          await card
            .getByRole("link", { name: "Read the call", exact: true })
            .click();
          await expect(
            anonymous.getByText("Public brief for publication browser tests."),
          ).toBeVisible();
          expect(
            (
              await outsider.request.get(`/calls/${slug}/specs/selected`)
            ).status(),
          ).toBe(404);
          const selection = new Selection(pool, gitlabId);
          const pair = { selected: choices[0], runnerUp: choices[1] };
          const copy = {
            introduction: "Published introduction.",
            selectedSummary: "Selected description.",
            runnerUpSummary: "Runner-up description.",
            learned: "Published lessons.",
          };
          const version = await selection.saveDraft(
            reviewer,
            token,
            slug,
            pair,
            copy,
            "0",
          );
          const decision = await selection.prepare(
            reviewer,
            token,
            slug,
            pair,
            version,
          );
          await selection.confirm(
            reviewer,
            token,
            slug,
            decision.confirmationToken,
            "confirm",
          );
          // Private drafts remain private even when they differ from the confirmed copy.
          await pool.query(
            "UPDATE selection_drafts SET copy=$1 WHERE call_slug=$2",
            [
              JSON.stringify({ ...copy, learned: `draft-secret-${marker}` }),
              slug,
            ],
          );
          await anonymous.reload();
          await expect(
            anonymous.getByText("Results forthcoming"),
          ).toBeVisible();
          await expect(anonymous.getByText(copy.introduction)).toHaveCount(0);
          for (const suffix of ["?/prepare", "?/publish", "?/cancel"]) {
            expect(
              (
                await outsider.request.post(base + "/publish" + suffix, {
                  headers: { Origin: origin },
                  form: { confirmationText: "publish" },
                })
              ).status(),
            ).toBe(404);
            expect(
              (
                await page.request.post(base + "/publish" + suffix, {
                  headers: { Origin: "https://example.invalid" },
                  form: { confirmationText: "publish" },
                })
              ).status(),
            ).toBe(403);
          }
          await page.goto(base);
          await page
            .getByRole("button", { name: "Publish results", exact: true })
            .click();
          await expect(
            page.getByRole("heading", { name: "Publish results", exact: true }),
          ).toBeVisible();
          await expect(
            page.getByText(
              "This results page and both funded specs will be readable without signing in. Other submissions stay private.",
            ),
          ).toBeVisible();
          await page
            .getByRole("button", { name: "Cancel", exact: true })
            .click();
          await expect(
            page.getByText("These results are private."),
          ).toBeVisible();
          await page
            .getByRole("button", { name: "Publish results", exact: true })
            .click();
          await page
            .getByLabel("Type publish to publish the results")
            .fill("wrong");
          await page
            .getByRole("button", { name: "Publish results", exact: true })
            .click();
          await expect(page.getByRole("alert")).toContainText("Type publish");
          await page
            .getByRole("button", { name: "Preview publication", exact: true })
            .click();
          await page
            .getByLabel("Type publish to publish the results")
            .fill("publish");
          await page
            .getByRole("button", { name: "Publish results", exact: true })
            .click();
          await expect(
            page.getByRole("link", {
              name: "View public results",
              exact: true,
            }),
          ).toBeVisible();
          await expect(
            page.getByText("These results are private."),
          ).toHaveCount(0);
          await anonymous.goto(`/calls/${slug}`);
          await expect(
            anonymous.getByRole("heading", {
              name: `Publication test ${info.project.name}`,
              level: 1,
            }),
          ).toBeVisible();
          await expect(anonymous.getByText(copy.learned)).toBeVisible();
          await expect(anonymous.locator('a[href^="/review"]')).toHaveCount(0);
          const payload = await anonymous.evaluate(
            async (path) => (await fetch(path)).text(),
            `/calls/${slug}/__data.json`,
          );
          for (const forbidden of [
            "private-contact@example.invalid",
            "private-author@example.invalid",
            `Unselected secret ${marker}`,
            `draft-secret-${marker}`,
            `consent-${marker}`,
            "confirmedByGitlabId",
            "submissionId",
            "revisionId",
            "Published body",
          ])
            expect(payload).not.toContain(forbidden);
          await anonymous
            .getByRole("link", { name: "Read the selected spec", exact: true })
            .click();
          await expect(
            anonymous.getByRole("heading", {
              name: "Funded proposal 0",
              exact: true,
            }),
          ).toBeVisible();
          await expect(
            anonymous.getByText("Published body 0.", { exact: true }),
          ).toBeVisible();
          await expect(
            anonymous.locator(
              ".published-reading img, .published-reading script",
            ),
          ).toHaveCount(0);
          await anonymous.goto(`/calls/${slug}/specs/runner-up`);
          await expect(
            anonymous.getByRole("heading", {
              name: "Funded proposal 1",
              exact: true,
            }),
          ).toBeVisible();
          expect(
            (
              await outsider.request.get(
                `/calls/${slug}/specs/${choices[2].revisionId}`,
              )
            ).status(),
          ).toBe(404);
          await anonymous.goto("/");
          await expect(
            card.getByRole("link", { name: "Read the results", exact: true }),
          ).toBeVisible();
          await expect(card.locator(".award-amounts")).toContainText(
            "Public author 0",
          );
          await expect(card.locator(".award-amounts")).toContainText(
            "Public author 1",
          );
          await expect(card).not.toContainText("Public author 2");
          await expect(card.locator(".award-dates")).toContainText("Closed");
          await expect(card.locator(".award-dates")).toHaveCSS(
            "border-top-width",
            "1px",
          );
          const dividers = await anonymous
            .locator("#previous-calls .call-card")
            .evaluateAll((cards) =>
              cards.map((card, index) => ({
                bottom: parseFloat(getComputedStyle(card).borderBottomWidth),
                last: index === cards.length - 1,
              })),
            );
          expect(dividers.slice(0, -1).every((card) => card.bottom === 0)).toBe(
            true,
          );
        } finally {
          await outsider.close();
          await pool.query(
            "DELETE FROM publication_confirmations WHERE call_slug=$1",
            [slug],
          );
          await pool.query("DELETE FROM call_publications WHERE call_slug=$1", [
            slug,
          ]);
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
            "UPDATE submissions SET current_revision_id=NULL WHERE call_slug=$1",
            [slug],
          );
          await pool.query(
            "DELETE FROM submission_revisions WHERE submission_id IN (SELECT id FROM submissions WHERE call_slug=$1)",
            [slug],
          );
          await pool.query("DELETE FROM submissions WHERE call_slug=$1", [
            slug,
          ]);
          await pool.query("DELETE FROM call_contracts WHERE slug=$1", [slug]);
          await pool.query("DELETE FROM agreement_snapshots WHERE sha256=$1", [
            digest(marker),
          ]);
          await pool.query(
            "DELETE FROM sessions WHERE user_id=ANY($1::bigint[])",
            [ids],
          );
          await pool.query("DELETE FROM users WHERE id=ANY($1::bigint[])", [
            ids,
          ]);
          await pool.end();
        }
      });
    },
  );
}
