import { testDatabaseUrl } from "./database.ts";
import { before, after, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { Pool } from "pg";
import { unzipSync, strFromU8 } from "fflate";
import { createPool } from "../src/lib/server/database.ts";
import {
  submit,
  digest,
  type Contract,
} from "../src/lib/server/submissions.ts";
import {
  Review,
  ReviewDenied,
  ReviewLimit,
  reviewerIds,
  isReviewer,
} from "../src/lib/server/review.ts";

const url = testDatabaseUrl();
const admin = createPool(url);
const schema = `review_test_${randomBytes(8).toString("hex")}`;
const pool = new Pool({
  connectionString: url,
  options: `-c search_path=${schema}`,
});
const author = { id: "1", gitlabId: "123", username: "author", name: "Author" };
const reviewer = {
  id: "2",
  gitlabId: "999",
  username: "reviewer",
  name: "Reviewer",
};
const service = new Review(pool, "999");
let contract: Contract;
const agreement = (version: string) => ({
  version,
  body: version,
  sha256: digest(version),
});
function form(expected = "", markdown = "# Private spec") {
  const data = new FormData();
  for (const [key, value] of Object.entries({
    email: "private@example.org",
    author: "Spec Author",
    authorEmail: "git@example.org",
    acceptedCla: "on",
    acceptedTerms: "on",
    expectedRevision: expected,
    claVersion: contract.cla.version,
    termsVersion: contract.terms.version,
    claHash: contract.cla.sha256,
    termsHash: contract.terms.sha256,
  }))
    data.set(key, value);
  data.set("file", new File([markdown], "spec.md"));
  return data;
}
async function submissionId() {
  return (
    await pool.query("SELECT id FROM submissions WHERE user_id=$1", [author.id])
  ).rows[0].id as string;
}

before(async () => {
  await admin.query(`CREATE SCHEMA ${schema}`);
  for (const name of [
    "001_auth.sql",
    "002_submissions.sql",
    "005_contract_history.sql",
  ])
    await pool.query(
      await readFile(new URL(`../migrations/${name}`, import.meta.url), "utf8"),
    );
});
beforeEach(async () => {
  await pool.query(
    "TRUNCATE users, sessions, submissions, submission_revisions, call_contracts, call_contract_history, agreement_snapshots RESTART IDENTITY CASCADE",
  );
  await pool.query(
    "INSERT INTO users (gitlab_user_id,gitlab_username,display_name) VALUES (123,'author','Author'),(999,'reviewer','Reviewer')",
  );
  contract = {
    slug: "test-call",
    opensAt: new Date(Date.now() - 60000).toISOString(),
    closesAt: new Date(Date.now() + 60000).toISOString(),
    selectedAmountMinor: 50000,
    runnerUpAmountMinor: 25000,
    currency: "EUR",
    mode: "rehearsal",
    cla: agreement("cla-v1"),
    terms: agreement("terms-v1"),
  };
});
after(async () => {
  await pool.end();
  await admin.query(`DROP SCHEMA ${schema} CASCADE`);
  await admin.end();
});

test("only explicitly configured numeric provider IDs grant access", () => {
  for (const value of [
    undefined,
    "",
    " ",
    "999,",
    "999,admin",
    "0999",
    "-999",
    "9.99e2",
    "9007199254740992",
  ])
    assert.equal(reviewerIds(value).size, 0);
  assert.deepEqual([...reviewerIds(" 999,123,999 ")], ["999", "123"]);
  assert.equal(isReviewer(reviewer, "999"), true);
  assert.equal(isReviewer({ ...author, username: "reviewer" }, "999"), false);
});

test("every operation denies anonymous and non-reviewer accounts, including revoked access", async () => {
  await submit(pool, author, contract, form());
  const id = await submissionId();
  for (const user of [null, author]) {
    await assert.rejects(service.list(user, contract.slug), ReviewDenied);
    await assert.rejects(service.detail(user, contract.slug, id), ReviewDenied);
    await assert.rejects(service.archive(user, contract.slug), ReviewDenied);
  }
  const revoked = new Review(pool, "");
  await assert.rejects(revoked.list(reviewer, contract.slug), ReviewDenied);
  await assert.rejects(
    revoked.detail(reviewer, contract.slug, id),
    ReviewDenied,
  );
  await assert.rejects(revoked.archive(reviewer, contract.slug), ReviewDenied);
});

test("review loads current revisions with a minimal index and call-scoped details", async () => {
  assert.deepEqual((await service.list(reviewer, contract.slug)).entries, []);
  const first = await submit(pool, author, contract, form());
  const id = await submissionId();
  const next = await submit(
    pool,
    author,
    contract,
    form(first.id, "# Updated spec"),
  );
  const index = await service.list(reviewer, contract.slug);
  assert.deepEqual(index.entries, [
    {
      id,
      revisionId: next.id,
      author: "Spec Author",
      filename: "spec.md",
      title: "Updated spec",
    },
  ]);
  const selected = await service.detail(reviewer, contract.slug, id);
  assert.equal(selected!.markdown, "# Updated spec");
  assert.equal(selected!.email, "private@example.org");
  assert.equal(selected!.authorEmail, "git@example.org");
  assert.equal(await service.detail(reviewer, "another-call", id), null);
  for (const invalid of [
    "0",
    "nope",
    "9223372036854775808",
    "999999999999999999999",
    "999999",
  ])
    assert.equal(await service.detail(reviewer, contract.slug, invalid), null);
});

test("archives contain current Markdown, stable filenames and hashes without contact metadata", async () => {
  const first = await submit(pool, author, contract, form());
  const next = await submit(
    pool,
    author,
    contract,
    form(first.id, "# Current spec"),
  );
  const files = unzipSync(await service.archive(reviewer, contract.slug));
  const index = JSON.parse(strFromU8(files["index.json"]));
  assert.equal(index.length, 1);
  assert.equal(index[0].revisionId, next.id);
  assert.equal(strFromU8(files[index[0].filename]), "# Current spec");
  assert.equal(index[0].sha256, digest("# Current spec"));
  assert.deepEqual(Object.keys(index[0]).sort(), [
    "author",
    "filename",
    "revisionId",
    "sha256",
    "submissionId",
  ]);
  for (const bytes of Object.values(files)) {
    assert.ok(!strFromU8(bytes).includes("private@example.org"));
    assert.ok(!strFromU8(bytes).includes("git@example.org"));
  }
});

test("archive snapshot stays consistent during a concurrent replacement", async () => {
  const first = await submit(pool, author, contract, form());
  const wrapped = {
    connect: async () => {
      const client = await pool.connect();
      return {
        query: async (sql: string, values?: unknown[]) => {
          const result = await client.query(sql, values);
          if (sql.includes("octet_length"))
            await submit(
              pool,
              author,
              contract,
              form(first.id, "# Concurrent replacement"),
            );
          return result;
        },
        release: () => client.release(),
      };
    },
  } as unknown as Pool;
  const files = unzipSync(
    await new Review(wrapped, "999").archive(reviewer, contract.slug),
  );
  const index = JSON.parse(strFromU8(files["index.json"]));
  assert.equal(index[0].revisionId, first.id);
  assert.equal(strFromU8(files[index[0].filename]), "# Private spec");
  assert.equal(
    (await service.detail(reviewer, contract.slug, await submissionId()))!
      .markdown,
    "# Concurrent replacement",
  );
});

async function addSubmissions(count: number, markdown: string) {
  const userIds = (
    await pool.query(
      "INSERT INTO users (gitlab_user_id,gitlab_username,display_name) SELECT n+1000,'extra-'||n,'Extra' FROM generate_series(1,$1::int) n RETURNING id",
      [count],
    )
  ).rows.map((row) => row.id);
  await pool.query(
    "INSERT INTO submissions (call_slug,user_id) SELECT $1,unnest($2::bigint[])",
    [contract.slug, userIds],
  );
  await pool.query(
    `WITH added AS (
    INSERT INTO submission_revisions (submission_id,markdown,filename,sha256,received_at,contact_email,author_name,author_email,cla_sha256,terms_sha256,consent)
    SELECT s.id,$1,'extra.md',$2,clock_timestamp(),'contact@example.org','Extra','author@example.org',$3,$4,'{}'::jsonb
    FROM submissions s WHERE user_id=ANY($5::bigint[]) RETURNING id,submission_id
  ) UPDATE submissions SET current_revision_id=added.id FROM added WHERE submissions.id=added.submission_id`,
    [
      markdown,
      digest(markdown),
      contract.cla.sha256,
      contract.terms.sha256,
      userIds,
    ],
  );
}

test("indexes paginate and oversized entry counts fail before exporting", async () => {
  await submit(pool, author, contract, form());
  await addSubmissions(200, "# Extra");
  const first = await service.list(reviewer, contract.slug);
  const second = await service.list(reviewer, contract.slug, 2);
  assert.equal(first.entries.length, 50);
  assert.equal(first.hasNext, true);
  assert.ok(
    second.entries.every(
      (row) => !first.entries.some((previous) => previous.id === row.id),
    ),
  );
  await assert.rejects(service.archive(reviewer, contract.slug), ReviewLimit);
});

test("archive byte limits use UTF-8 byte counts", async () => {
  await submit(pool, author, contract, form());
  await addSubmissions(64, "ø".repeat(128 * 1024));
  await assert.rejects(service.archive(reviewer, contract.slug), ReviewLimit);
});

test("failed rollback discards the connection without hiding the original error", async () => {
  const failure = new Error("connection lost");
  let discarded = false;
  const disconnected = {
    connect: async () => ({
      query: async (sql: string) => {
        if (sql.startsWith("BEGIN")) return;
        if (sql === "ROLLBACK") throw new Error("rollback failed");
        throw failure;
      },
      release: (discard: boolean) => {
        discarded = discard;
      },
    }),
  } as unknown as Pool;
  await assert.rejects(
    new Review(disconnected, "999").archive(reviewer, contract.slug),
    (error) => error === failure,
  );
  assert.equal(discarded, true);
});

test("call overview includes empty configured calls and retained history without exposing submissions", async () => {
  const first = await submit(pool, author, contract, form());
  await submit(
    pool,
    author,
    contract,
    form(first.id, "# Revised current call"),
  );
  const old = { ...contract, slug: "old-call" };
  const saved = await submit(pool, author, old, form("", "# Historical spec"));
  const closed = {
    ...old,
    opensAt: "2020-01-01T00:00:00Z",
    closesAt: "2020-02-01T00:00:00Z",
  };
  await pool.query(
    "UPDATE call_contracts SET snapshot=$2,sha256=$3 WHERE slug=$1",
    [closed.slug, JSON.stringify(closed), digest(JSON.stringify(closed))],
  );
  const configured = [
    {
      slug: contract.slug,
      title: "Current call",
      opensAt: contract.opensAt,
      closesAt: "2099-01-01T00:00:00Z",
      timeZone: "Europe/Copenhagen",
      briefHref: "/calls/test-call",
    },
    {
      slug: "upcoming",
      title: "Future call",
      opensAt: "2099-01-01T00:00:00Z",
      closesAt: "2099-02-01T00:00:00Z",
      timeZone: "UTC",
      briefHref: null,
    },
  ];
  const calls = await service.calls(reviewer, configured);
  assert.deepEqual(
    calls.map((call) => call.slug),
    [contract.slug, "upcoming", "old-call"],
  );
  assert.equal(calls[0].submissions, 1);
  assert.equal(calls[0].closesAt, contract.closesAt);
  assert.equal(calls[1].submissions, 0);
  assert.equal(calls[2].status, "closed");
  assert.equal(calls[2].title, "old-call");
  assert.equal(calls[2].contentAvailable, false);
  assert.equal(calls[2].briefHref, null);
  assert.equal(calls[2].submissions, 1);
  assert.ok(!JSON.stringify(calls).includes("Historical spec"));
  assert.ok(!JSON.stringify(calls).includes("private@example.org"));
  for (const user of [null, author])
    await assert.rejects(service.calls(user, configured), ReviewDenied);
  assert.deepEqual(
    await service.calls(reviewer, configured, { slug: "unknown" }),
    [],
  );
  const closedId = (
    await pool.query("SELECT id FROM submissions WHERE call_slug=$1", [
      old.slug,
    ])
  ).rows[0].id;
  assert.equal(
    (await service.detail(reviewer, old.slug, closedId))!.markdown,
    "# Historical spec",
  );
  assert.equal(await service.detail(reviewer, contract.slug, closedId), null);
  const archive = unzipSync(await service.archive(reviewer, old.slug));
  const index = JSON.parse(strFromU8(archive["index.json"]));
  assert.equal(index.length, 1);
  assert.equal(strFromU8(archive[index[0].filename]), "# Historical spec");
  await assert.rejects(submit(pool, author, closed, form(saved.id)), /closed/);
  assert.equal(
    (await service.detail(reviewer, old.slug, closedId))!.revisionId,
    saved.id,
  );
});
