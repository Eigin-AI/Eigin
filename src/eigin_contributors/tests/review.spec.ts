import { testDatabaseUrl } from "./database.ts";
import { test, expect } from "@playwright/test";
import { randomBytes } from "node:crypto";
import { unzipSync, strFromU8 } from "fflate";
import {
  submit,
  digest,
  type Contract,
} from "../src/lib/server/submissions.ts";
import { Auth } from "../src/lib/server/auth.ts";
import { createPool } from "../src/lib/server/database.ts";

const origin = "http://localhost:5276";
test("review is private, shows current specs, and downloads server-side exports", async ({
  page,
  context,
  browser,
}, info) => {
  test.setTimeout(60_000);
  const pool = createPool(testDatabaseUrl());
  const reviewerId =
    info.project.name === "desktop" ? 700000000001 : 700000000002;
  const authorId = 8100000000000000 + Math.floor(Math.random() * 1000000000);
  const marker = randomBytes(6).toString("hex");
  const authorName = `Review fixture ${marker}`;
  const authorContext = await browser.newContext({ baseURL: origin });
  const authorPage = await authorContext.newPage();
  const historicalSlug = `history-${marker}`;
  const accounts: { auth: Auth; token: string; userId: string }[] = [];
  async function login(id: number) {
    const auth = new Auth(
      pool,
      { origin, clientId: "test", clientSecret: "test" },
      async (input) =>
        Response.json(
          String(input).endsWith("/oauth/token")
            ? { access_token: "test" }
            : { id, username: `review-test-${id}`, name: "Review Test" },
        ),
    );
    const attempt = await auth.begin();
    const session = await auth.complete(
      attempt.binding,
      new URL(attempt.url).searchParams.get("state"),
      "test-code",
    );
    const user = (await auth.user(session.token))!;
    accounts.push({ auth, token: session.token, userId: user.id });
    return {
      user,
      cookie: {
        name: "contributors_session",
        value: session.token,
        url: origin,
        httpOnly: true,
        sameSite: "Lax" as const,
      },
    };
  }
  try {
    const author = await login(authorId);
    await authorContext.addCookies([author.cookie]);
    await authorPage.goto(`${origin}/calls/tool-safety/submission`);
    const fields: Record<string, string> = {};
    for (const key of ["claVersion", "termsVersion", "claHash", "termsHash"])
      fields[key] = await authorPage
        .locator(`input[name="${key}"]`)
        .inputValue();
    async function save(expectedRevision: string, markdown: string) {
      const response = await authorContext.request.post(
        `${origin}/calls/tool-safety/submission`,
        {
          headers: { Origin: origin },
          multipart: {
            ...fields,
            expectedRevision,
            email: `${marker}@private.example`,
            author: authorName,
            authorEmail: `${marker}@git.example`,
            acceptedCla: "on",
            acceptedTerms: "on",
            file: {
              name: "review-fixture.md",
              mimeType: "text/markdown",
              buffer: Buffer.from(markdown),
            },
          },
        },
      );
      expect(response.status()).toBe(200);
    }
    await save("", `# Old spec ${marker}`);
    const submission = (
      await pool.query(
        "SELECT id,current_revision_id FROM submissions WHERE user_id=$1",
        [author.user.id],
      )
    ).rows[0];
    const markdown = `# Current spec ${marker}\n\nPrepared for review.\n\n| Approach | Fallback |\n| --- | --- |\n| Local rules | Ask for approval |\n\n- [x] **Reviewed** [safe reference](https://example.invalid/context)\n  - [ ] Nested task\n\n<script>alert('unsafe')</script>\n\n![remote](https://example.invalid/review.png)`;
    await save(submission.current_revision_id, markdown);
    const historicalContract: Contract = {
      ...(
        await pool.query(
          "SELECT snapshot FROM call_contracts WHERE slug='tool-safety'",
        )
      ).rows[0].snapshot,
      slug: historicalSlug,
      opensAt: new Date(Date.now() - 60000).toISOString(),
      closesAt: new Date(Date.now() + 60000).toISOString(),
    };
    const historicalForm = new FormData();
    for (const [key, value] of Object.entries({
      ...fields,
      email: `${marker}@private.example`,
      author: authorName,
      authorEmail: `${marker}@git.example`,
      acceptedCla: "on",
      acceptedTerms: "on",
    }))
      historicalForm.set(key, value);
    historicalForm.set(
      "file",
      new File([`# Historical ${marker}`], "history.md"),
    );
    await submit(pool, author.user, historicalContract, historicalForm);
    historicalContract.opensAt = "2020-01-01T00:00:00Z";
    historicalContract.closesAt = "2020-02-01T00:00:00Z";
    await pool.query(
      "UPDATE call_contracts SET snapshot=$2,sha256=$3 WHERE slug=$1",
      [
        historicalSlug,
        JSON.stringify(historicalContract),
        digest(JSON.stringify(historicalContract)),
      ],
    );
    const historical = (
      await pool.query(
        "SELECT id FROM submissions WHERE user_id=$1 AND call_slug=$2",
        [author.user.id, historicalSlug],
      )
    ).rows[0];
    const historicalPath = `/review/calls/${historicalSlug}`;
    const paths = [
      "/review",
      "/review/calls/tool-safety",
      "/review/calls/tool-safety/brief",
      historicalPath,
      `${historicalPath}/submissions/${historical.id}`,
      `${historicalPath}/submissions/${historical.id}/download`,
      `${historicalPath}/archive`,
      `/review/calls/tool-safety/submissions/${submission.id}`,
      `/review/calls/tool-safety/submissions/${submission.id}/download`,
      "/review/calls/tool-safety/archive",
    ];
    for (const client of [page.request, authorContext.request]) {
      for (const path of paths) {
        const response = await client.get(origin + path);
        expect(response.status()).toBe(404);
        expect(response.headers()["cache-control"]).toBe("no-store");
        expect((await response.text()).includes(authorName)).toBe(false);
        expect(
          (await response.text()).includes(`${marker}@private.example`),
        ).toBe(false);
      }
    }
    await authorPage.goto(origin);
    await expect(
      authorPage.locator('.site-header a[href="/review"]'),
    ).toHaveCount(0);
    const reviewer = await login(reviewerId);
    await context.addCookies([reviewer.cookie]);
    await page.goto("/account");
    await expect(
      page.getByText(`GitLab user ID: ${reviewerId}.`, { exact: false }),
    ).toBeVisible();
    const viewport = page.viewportSize()!;
    for (const width of [601, 768]) {
      await page.setViewportSize({ width, height: 900 });
      const brand = await page
        .locator(".site-header .site-brand")
        .boundingBox();
      const navigation = page.locator(".site-header .desktop-nav");
      const actions = await page
        .locator(".site-header .header-actions")
        .boundingBox();
      if (await navigation.isVisible()) {
        const box = await navigation.boundingBox();
        expect(brand!.x + brand!.width).toBeLessThanOrEqual(box!.x);
        expect(box!.x + box!.width).toBeLessThanOrEqual(actions!.x);
      } else {
        await expect(page.locator(".site-header .mobile-menu")).toBeVisible();
        expect(brand!.x + brand!.width).toBeLessThanOrEqual(actions!.x);
      }
    }
    await page.setViewportSize(viewport);
    await page
      .getByRole("link", { name: "Review submissions", exact: true })
      .click();
    await expect(
      page.getByRole("heading", { name: "Review calls.", exact: true }),
    ).toBeVisible();
    await page
      .getByRole("link", { name: /Local detection of malicious instructions/ })
      .click();
    await expect(
      page.getByRole("heading", { name: "Read the specs.", exact: true }),
    ).toBeVisible();
    await expect(
      page.locator('.site-header a[href="/review"]').first(),
    ).toBeAttached();
    const brief = page.getByRole("article", {
      name: "Call brief",
      exact: true,
    });
    await expect(
      brief.getByRole("heading", { name: "The problem", exact: true }),
    ).toBeVisible();
    await expect(brief.locator(".call-constraints details")).toHaveCount(7);
    await brief.locator("summary").filter({ hasText: "Local-first" }).click();
    await expect(
      brief.getByText(
        "Runs on the device without round-tripping a hosted model or service.",
      ),
    ).toBeVisible();
    const originalBrief = (await brief.textContent()) ?? "";
    await page.goto("/review/calls/tool-safety/brief");
    await expect(page).toHaveURL(/\/review\/calls\/tool-safety$/);
    await expect(brief).toHaveText(originalBrief);
    const listResponse = await page.request.get("/review/calls/tool-safety");
    expect(await listResponse.text()).toContain(`Current spec ${marker}`);
    expect(await listResponse.text()).not.toContain("Prepared for review.");
    expect(await listResponse.text()).not.toContain(
      `${marker}@private.example`,
    );
    await page
      .locator(".review-index")
      .getByRole("link")
      .filter({ hasText: authorName })
      .click();
    await expect(
      page.getByRole("heading", {
        name: `Current spec ${marker}`,
        exact: true,
      }),
    ).toBeVisible();
    await expect(
      page.getByRole("article", { name: "Call brief", exact: true }),
    ).toHaveCount(0);
    await expect(page.locator(".review-contact")).toContainText(
      `${marker}@private.example`,
    );
    await expect(
      page.locator(".review-reading img, .review-reading script"),
    ).toHaveCount(0);
    const tasks = page.locator(".review-reading .task-marker");
    await expect(tasks).toHaveCount(2);
    await expect(tasks.first()).toHaveAttribute("aria-checked", "true");
    await expect(tasks.nth(1)).toHaveAttribute("aria-checked", "false");
    await expect(page.locator(".review-reading strong")).toHaveText("Reviewed");
    await expect(
      page.getByRole("link", { name: "safe reference", exact: true }),
    ).toHaveAttribute("href", "https://example.invalid/context");
    await expect(
      page.locator('.review-reading input[type="checkbox"]'),
    ).toHaveCount(0);
    const table = page.locator(".review-reading table");
    await expect(table.locator("th")).toHaveCount(2);
    await expect(table.locator("td")).toHaveCount(2);
    const tableLayout = await table.evaluate((element) => {
      const cells = element.querySelectorAll("td");
      return {
        collapse: getComputedStyle(element).borderCollapse,
        gap:
          cells[1].getBoundingClientRect().left -
          cells[0].getBoundingClientRect().right,
      };
    });
    expect(tableLayout.collapse).toBe("collapse");
    expect(Math.abs(tableLayout.gap)).toBeLessThan(1);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const detailResponse = await page.request.get(
      `/review/calls/tool-safety/submissions/${submission.id}`,
    );
    expect(detailResponse.headers()["cache-control"]).toBe("no-store");
    expect(detailResponse.headers()["referrer-policy"]).toBe("same-origin");
    const download = await page.request.get(
      `/review/calls/tool-safety/submissions/${submission.id}/download`,
    );
    expect(download.status()).toBe(200);
    expect(await download.text()).toBe(markdown);
    expect(download.headers()["content-disposition"]).toMatch(
      /^attachment; filename="submission-\d+-revision-\d+\.md"$/,
    );
    expect(download.headers()["x-content-type-options"]).toBe("nosniff");
    const archive = await page.request.get("/review/calls/tool-safety/archive");
    expect(archive.status()).toBe(200);
    expect(archive.headers()["cache-control"]).toBe("no-store");
    const files = unzipSync(new Uint8Array(await archive.body()));
    const index = JSON.parse(strFromU8(files["index.json"]));
    const own = index.find(
      (entry: { submissionId: string }) => entry.submissionId === submission.id,
    );
    expect(strFromU8(files[own.filename])).toBe(markdown);
    expect(strFromU8(files["index.json"])).not.toContain(
      `${marker}@private.example`,
    );
    expect(strFromU8(files["index.json"])).not.toContain(
      `${marker}@git.example`,
    );
    expect(
      (await page.request.get("/review/calls/unknown/archive")).status(),
    ).toBe(404);
    expect(
      (
        await page.request.get(
          "/review/calls/tool-safety/submissions/9223372036854775808/download",
        )
      ).status(),
    ).toBe(404);
    await page.getByRole("link", { name: "All calls", exact: true }).click();
    await page
      .getByRole("region", { name: "Closed calls", exact: true })
      .getByRole("link", { name: new RegExp(historicalSlug) })
      .click();
    await expect(
      page.getByText("The original call title and brief are unavailable.", {
        exact: false,
      }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Read the call", exact: true }),
    ).toHaveCount(0);
    await expect(
      page.getByText(
        "The original call brief is unavailable. Choose a submission to read its latest saved revision.",
      ),
    ).toBeVisible();
    await page
      .locator(".review-index")
      .getByRole("link")
      .filter({ hasText: authorName })
      .click();
    await expect(
      page.getByRole("heading", { name: `Historical ${marker}`, exact: true }),
    ).toBeVisible();
    const historicalDownload = await page.request.get(
      `${historicalPath}/submissions/${historical.id}/download`,
    );
    expect(await historicalDownload.text()).toBe(`# Historical ${marker}`);
    const historicalArchive = unzipSync(
      new Uint8Array(
        await (await page.request.get(`${historicalPath}/archive`)).body(),
      ),
    );
    const historicalIndex = JSON.parse(
      strFromU8(historicalArchive["index.json"]),
    );
    expect(historicalIndex).toHaveLength(1);
    expect(strFromU8(historicalArchive[historicalIndex[0].filename])).toBe(
      `# Historical ${marker}`,
    );
    expect(
      (
        await page.request.get(`${historicalPath}/submissions/${submission.id}`)
      ).status(),
    ).toBe(404);
    expect(
      (
        await page.request.get(
          `${historicalPath}/submissions/${submission.id}/download`,
        )
      ).status(),
    ).toBe(404);
    expect(
      (
        await page.request.get(
          `/review/calls/tool-safety/submissions/${historical.id}/download`,
        )
      ).status(),
    ).toBe(404);
    await page.getByRole("button", { name: "Sign out", exact: true }).click();
    await expect(
      page.getByRole("link", { name: "Sign in", exact: true }),
    ).toBeVisible();
    for (const path of paths)
      expect((await page.request.get(path)).status()).toBe(404);
  } finally {
    await authorContext.close();
    for (const account of accounts) {
      await account.auth.logout(account.token);
      await pool.query(
        "UPDATE submissions SET current_revision_id=NULL WHERE user_id=$1",
        [account.userId],
      );
      await pool.query(
        "DELETE FROM submission_revisions WHERE submission_id IN (SELECT id FROM submissions WHERE user_id=$1)",
        [account.userId],
      );
      await pool.query("DELETE FROM submissions WHERE user_id=$1", [
        account.userId,
      ]);
      await pool.query("DELETE FROM users WHERE id=$1", [account.userId]);
    }
    await pool.query("DELETE FROM call_contracts WHERE slug=$1", [
      historicalSlug,
    ]);
    await pool.end();
  }
});
