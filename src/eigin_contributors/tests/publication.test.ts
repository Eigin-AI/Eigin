import { testDatabaseUrl } from "./database.ts";
import { callStatus } from "../src/lib/call-status.ts";
import { Publication } from "../src/lib/server/publication.ts";
import { PublishedCalls } from "../src/lib/server/published-calls.ts";
import type { PublicCall } from "../src/lib/publication.ts";
import { before, after, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { Pool } from "pg";
import { createPool } from "../src/lib/server/database.ts";
import {
  submit,
  digest,
  type Contract,
} from "../src/lib/server/submissions.ts";
import {
  Selection,
  SelectionFailure,
  type Pair,
} from "../src/lib/server/selection.ts";
import { ReviewDenied } from "../src/lib/server/review.ts";

const url = testDatabaseUrl();
const admin = createPool(url);
const schema = `publication_test_${randomBytes(8).toString("hex")}`;
const pool = new Pool({
  connectionString: url,
  options: `-c search_path=${schema}`,
});
const service = new Selection(pool, "999,998");
const reviewer = {
  id: "3",
  gitlabId: "999",
  username: "reviewer",
  name: "Reviewer",
};
const second = { id: "4", gitlabId: "998", username: "second", name: "Second" };
const author = { id: "1", gitlabId: "123", username: "author", name: "Author" };
let contract: Contract;
let pair: Pair;
const agreement = { version: "test", body: "test", sha256: digest("test") };
async function changeContract(changes: Partial<Contract>) {
  contract = { ...contract, ...changes };
  await pool.query(
    "UPDATE call_contracts SET snapshot=$1,sha256=$2 WHERE slug=$3",
    [JSON.stringify(contract), digest(JSON.stringify(contract)), contract.slug],
  );
}
const copy = {
  introduction: "Two useful approaches.",
  selectedSummary: "A bounded rule set.",
  runnerUpSummary: "A small classifier.",
  learned: "Keep approval for uncertainty.",
};
async function ready() {
  const draft = await service.draft(reviewer, contract.slug);
  const version =
    draft?.version ??
    (await service.saveDraft(
      reviewer,
      "session-a",
      contract.slug,
      pair,
      copy,
      "0",
    ));
  return service.prepare(reviewer, "session-a", contract.slug, pair, version);
}
async function confirm(token: string) {
  return service.confirm(
    reviewer,
    "session-a",
    contract.slug,
    token,
    "confirm",
  );
}
async function count(table: string) {
  return Number(
    (await pool.query(`SELECT count(*) FROM ${table}`)).rows[0].count,
  );
}
before(async () => {
  await admin.query(`CREATE SCHEMA ${schema}`);
  for (const name of [
    "001_auth.sql",
    "002_submissions.sql",
    "005_contract_history.sql",
    "006_review_selection.sql",
    "007_selection_results.sql",
    "008_call_publications.sql",
  ])
    await pool.query(
      await readFile(new URL(`../migrations/${name}`, import.meta.url), "utf8"),
    );
});
beforeEach(async () => {
  await pool.query(
    "TRUNCATE users,call_contracts,agreement_snapshots RESTART IDENTITY CASCADE",
  );
  await pool.query(
    "INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES (123,'author','Author'),(124,'runner','Runner'),(999,'reviewer','Reviewer'),(998,'second','Second'),(125,'unselected','Unselected')",
  );
  for (const [token, id] of [
    ["session-a", "3"],
    ["session-b", "4"],
    ["other-session", "3"],
  ])
    await pool.query(
      "INSERT INTO sessions VALUES ($1,$2,clock_timestamp()+interval '1 hour')",
      [digest(token), id],
    );
  contract = {
    slug: "closed-call",
    opensAt: new Date(Date.now() - 60000).toISOString(),
    closesAt: new Date(Date.now() + 60000).toISOString(),
    selectedAmountMinor: 50000,
    runnerUpAmountMinor: 25000,
    currency: "EUR",
    mode: "rehearsal",
    cla: agreement,
    terms: agreement,
  };
  for (const [id, gitlabId, name] of [
    ["1", "123", "Author"],
    ["2", "124", "Runner"],
    ["5", "125", "Unselected"],
  ]) {
    const form = new FormData();
    for (const [key, value] of Object.entries({
      email: "private@example.org",
      author: name,
      authorEmail: "git@example.org",
      acceptedCla: "on",
      acceptedTerms: "on",
      claVersion: "test",
      termsVersion: "test",
      claHash: agreement.sha256,
      termsHash: agreement.sha256,
    }))
      form.set(key, value);
    form.set(
      "file",
      new File([`# ${name} proposal\n\nPrivate content.`], "spec.md"),
    );
    await submit(pool, { id, gitlabId, username: name, name }, contract, form);
  }
  const rows = (
    await pool.query(
      "SELECT id,current_revision_id FROM submissions ORDER BY id",
    )
  ).rows;
  pair = {
    selected: {
      submissionId: rows[0].id,
      revisionId: rows[0].current_revision_id,
    },
    runnerUp: {
      submissionId: rows[1].id,
      revisionId: rows[1].current_revision_id,
    },
  };
  await changeContract({ closesAt: new Date(Date.now() - 1000).toISOString() });
});
after(async () => {
  await pool.end();
  await admin.query(`DROP SCHEMA ${schema} CASCADE`);
  await admin.end();
});

const publication = new Publication(pool, "999,998");
function metadata(): PublicCall {
  return {
    ...contract,
    title: "Public call",
    summary: "A deliberately public brief.",
    brief: "# Public brief",
    publicListing: true,
    displayTimezone: "Europe/Copenhagen",
  };
}
const published = () => new PublishedCalls(pool, [metadata()]);
async function select() {
  await confirm((await ready()).confirmationToken);
}
async function prepare() {
  await select();
  return publication.prepare(reviewer, "session-a", contract.slug, metadata());
}
async function publish(token: string, call = metadata()) {
  await publication.publish(
    reviewer,
    "session-a",
    contract.slug,
    call,
    token,
    "publish",
  );
}

test("closed catalog shows public briefs while drafts and selections remain private", async () => {
  assert.equal((await published().list()).entries[0].publishedAt, null);
  assert.equal(await published().result(contract.slug), null);
  assert.equal(await published().spec(contract.slug, "selected"), null);
  await select();
  assert.equal(await published().result(contract.slug), null);
  assert.equal((await published().list()).entries[0].publishedAt, null);
  assert.equal((await new PublishedCalls(pool, []).list()).entries.length, 0);
});
test("publication exposes exactly the recorded pair and copy with narrow anonymous projections", async () => {
  const prepared = await prepare();
  assert.equal(await count("call_publications"), 0);
  const pending = (await pool.query("SELECT * FROM publication_confirmations"))
    .rows[0];
  assert.equal(pending.token_hash, digest(prepared.confirmationToken));
  await publish(prepared.confirmationToken);
  assert.equal(await count("publication_confirmations"), 0);
  const result = (await published().result(contract.slug))!;
  assert.deepEqual(result.copy, copy);
  assert.equal(result.selected.author, "Author");
  assert.equal(result.runnerUp.author, "Runner");
  assert.equal(result.selected.amountMinor, 50000);
  assert.equal(result.runnerUp.amountMinor, 25000);
  assert.equal(
    (await published().spec(contract.slug, "selected"))!.markdown,
    "# Author proposal\n\nPrivate content.",
  );
  assert.equal(
    (await published().spec(contract.slug, "runner-up"))!.author,
    "Runner",
  );
  assert.equal(
    await published().spec(contract.slug, pair.selected.revisionId),
    null,
  );
  const payload = JSON.stringify(result);
  for (const forbidden of [
    "markdown",
    "contact_email",
    "private@example.org",
    "git@example.org",
    "Unselected",
    "consent",
    "reviewer",
    "revisionId",
    "submissionId",
    "snapshot_sha256",
  ])
    assert.ok(!payload.includes(forbidden), forbidden);
  assert.ok((await published().list()).entries[0].publishedAt);
  const stored = (await pool.query("SELECT * FROM call_publications")).rows[0];
  assert.equal(stored.published_by_gitlab_id, reviewer.gitlabId);
  assert.equal(
    stored.snapshot_sha256,
    digest(JSON.stringify(prepared.preview)),
  );
  assert.ok(!JSON.stringify(stored.public_snapshot).includes("Unselected"));
});
test("rejects unauthorized reviewers and malformed allowlists independently of routes", async () => {
  await select();
  for (const user of [null, author]) {
    await assert.rejects(
      publication.prepare(user, "session-a", contract.slug, metadata()),
      ReviewDenied,
    );
    await assert.rejects(
      publication.publish(
        user,
        "session-a",
        contract.slug,
        metadata(),
        "a".repeat(64),
        "publish",
      ),
      ReviewDenied,
    );
    await assert.rejects(publication.status(user, contract.slug), ReviewDenied);
    await assert.rejects(
      publication.cancel(user, "session-a", contract.slug, "token"),
      ReviewDenied,
    );
  }
  await assert.rejects(
    new Publication(pool, "999,invalid").prepare(
      reviewer,
      "session-a",
      contract.slug,
      metadata(),
    ),
    ReviewDenied,
  );
});
test("tokens bind session, reviewer and exact text; failed attempts preserve pending confirmation", async () => {
  const p = await prepare();
  await assert.rejects(
    publication.publish(
      reviewer,
      "session-a",
      contract.slug,
      metadata(),
      p.confirmationToken,
      "confirm",
    ),
    /Type publish/,
  );
  await assert.rejects(publish("invalid"), /unavailable/);
  await assert.rejects(
    publication.publish(
      reviewer,
      "other-session",
      contract.slug,
      metadata(),
      p.confirmationToken,
      "publish",
    ),
    /unavailable/,
  );
  await assert.rejects(
    publication.publish(
      second,
      "session-b",
      contract.slug,
      metadata(),
      p.confirmationToken,
      "publish",
    ),
    /unavailable/,
  );
  assert.equal(await count("call_publications"), 0);
  assert.equal(await count("publication_confirmations"), 1);
  await publish(p.confirmationToken);
  await assert.rejects(publish(p.confirmationToken), /already been published/);
});
test("changed public metadata or recorded copy requires a fresh preview", async () => {
  const p = await prepare();
  await assert.rejects(
    publish(p.confirmationToken, { ...metadata(), title: "Changed" }),
    /unavailable/,
  );
  await pool.query("UPDATE call_selections SET results_copy=$1", [
    JSON.stringify({ ...copy, learned: "Changed" }),
  ]);
  await assert.rejects(publish(p.confirmationToken), /unavailable/);
  assert.equal(await count("call_publications"), 0);
});
test("expired confirmation and logged-out sessions cannot publish", async () => {
  const p = await prepare();
  await pool.query(
    "UPDATE publication_confirmations SET expires_at=clock_timestamp()-interval '1 second'",
  );
  await assert.rejects(publish(p.confirmationToken), /unavailable/);
  const next = await publication.prepare(
    reviewer,
    "session-a",
    contract.slug,
    metadata(),
  );
  await pool.query("DELETE FROM sessions WHERE token_hash=$1", [
    digest("session-a"),
  ]);
  assert.equal(await count("publication_confirmations"), 0);
  await assert.rejects(publish(next.confirmationToken), /unavailable/);
});
test("cancellation and preparing again revoke old tokens without publishing", async () => {
  const first = await prepare();
  const secondPreview = await publication.prepare(
    reviewer,
    "session-a",
    contract.slug,
    metadata(),
  );
  await assert.rejects(publish(first.confirmationToken), /unavailable/);
  await publication.cancel(
    reviewer,
    "session-a",
    contract.slug,
    secondPreview.confirmationToken,
  );
  await assert.rejects(publish(secondPreview.confirmationToken), /unavailable/);
  assert.equal(await count("call_publications"), 0);
});
test("missing content, private call metadata and incomplete confirmed copy block first publication", async () => {
  await assert.rejects(
    publication.prepare(reviewer, "session-a", contract.slug, metadata()),
    /complete recorded/,
  );
  await select();
  for (const call of [
    null,
    { ...metadata(), publicListing: false },
    { ...metadata(), brief: "" },
    { ...metadata(), slug: "wrong" },
  ])
    await assert.rejects(
      publication.prepare(reviewer, "session-a", contract.slug, call),
      /content is unavailable/,
    );
  await pool.query("UPDATE call_selections SET results_copy=NULL");
  await assert.rejects(
    publication.prepare(reviewer, "session-a", contract.slug, metadata()),
    SelectionFailure,
  );
});
test("concurrent reviewer publications produce a single immutable snapshot", async () => {
  const a = await prepare();
  const b = await publication.prepare(
    second,
    "session-b",
    contract.slug,
    metadata(),
  );
  const results = await Promise.allSettled([
    publish(a.confirmationToken),
    publication.publish(
      second,
      "session-b",
      contract.slug,
      metadata(),
      b.confirmationToken,
      "publish",
    ),
  ]);
  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(await count("call_publications"), 1);
  assert.equal(await count("publication_confirmations"), 0);
});
test("public snapshots survive metadata removal and current revision changes", async () => {
  const p = await prepare();
  await publish(p.confirmationToken);
  const before = await published().spec(contract.slug, "selected");
  await pool.query(
    "UPDATE submissions SET current_revision_id=NULL WHERE call_slug=$1",
    [contract.slug],
  );
  const withoutMetadata = new PublishedCalls(pool, []);
  assert.deepEqual(
    await withoutMetadata.spec(contract.slug, "selected"),
    before,
  );
  assert.equal((await withoutMetadata.list()).entries[0].title, "Public call");
});
test("catalog pagination is bounded, stable, and uses frozen deadlines and funding", async () => {
  const entries = Array.from({ length: 23 }, (_, i) => ({
    ...metadata(),
    slug: `public-${String(i).padStart(2, "0")}`,
  }));
  const catalog = new PublishedCalls(pool, entries);
  assert.equal((await catalog.list(1)).entries.length, 20);
  assert.equal((await catalog.list(1)).hasNext, true);
  assert.equal((await catalog.list(2)).entries.length, 3);
  assert.equal((await catalog.list(2)).hasNext, false);
  const changed = new PublishedCalls(pool, [
    { ...metadata(), closesAt: "2100-01-01T00:00:00Z", selectedAmountMinor: 1 },
  ]);
  assert.equal((await changed.list()).entries.length, 1);
  assert.equal((await changed.call(contract.slug))!.selectedAmountMinor, 50000);
  assert.equal((await changed.call(contract.slug))!.status, "closed");
  assert.equal(
    (
      await new PublishedCalls(pool, [
        { ...metadata(), slug: "future", closesAt: "2100-01-01T00:00:00Z" },
      ]).list()
    ).entries.length,
    0,
  );
});

test("database failure rolls back publication and leaves confirmation retryable", async () => {
  const prepared = await prepare();
  await pool.query(`CREATE FUNCTION reject_publication() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'synthetic insert failure'; END$$;
    CREATE TRIGGER reject_publication BEFORE INSERT ON call_publications FOR EACH ROW EXECUTE FUNCTION reject_publication()`);
  try {
    await assert.rejects(
      publish(prepared.confirmationToken),
      /synthetic insert failure/,
    );
    assert.equal(await count("call_publications"), 0);
    assert.equal(await count("publication_confirmations"), 1);
  } finally {
    await pool.query(
      "DROP TRIGGER reject_publication ON call_publications; DROP FUNCTION reject_publication()",
    );
  }
  await publish(prepared.confirmationToken);
  assert.equal(await count("call_publications"), 1);
});
test("an expired session cannot use an otherwise live publication token", async () => {
  const prepared = await prepare();
  await pool.query(
    "UPDATE sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE token_hash=$1",
    [digest("session-a")],
  );
  await assert.rejects(publish(prepared.confirmationToken), /unavailable/);
  assert.equal(await count("call_publications"), 0);
});
test("anonymous projections exclude unexpected stored fields", async () => {
  await publish((await prepare()).confirmationToken);
  await pool.query(
    `UPDATE call_publications SET public_snapshot=jsonb_set(public_snapshot, '{selected,privateField}', '"never public"')`,
  );
  assert.ok(
    !JSON.stringify(await published().result(contract.slug)).includes(
      "never public",
    ),
  );
  assert.ok(
    !JSON.stringify(await published().spec(contract.slug, "selected")).includes(
      "never public",
    ),
  );
});

test("catalog uses frozen opening and closing dates to report availability", async () => {
  await changeContract({
    opensAt: new Date(Date.now() + 60_000).toISOString(),
    closesAt: new Date(Date.now() + 120_000).toISOString(),
  });
  assert.equal((await published().call(contract.slug))!.status, "upcoming");
  assert.equal((await published().list()).entries.length, 0);
  await changeContract({
    opensAt: new Date(Date.now() - 60_000).toISOString(),
  });
  assert.equal((await published().call(contract.slug))!.status, "open");
  await changeContract({ closesAt: new Date(Date.now() - 1000).toISOString() });
  assert.equal((await published().call(contract.slug))!.status, "closed");
});

test("call availability includes the opening instant and excludes the closing instant", () => {
  const opening = Date.parse("2020-01-01T00:00:00Z"),
    closing = opening + 1000;
  const opensAt = new Date(opening).toISOString(),
    closesAt = new Date(closing).toISOString();
  assert.equal(callStatus(opensAt, closesAt, opening - 1), "upcoming");
  assert.equal(callStatus(opensAt, closesAt, opening), "open");
  assert.equal(callStatus(opensAt, closesAt, closing - 1), "open");
  assert.equal(callStatus(opensAt, closesAt, closing), "closed");
});
