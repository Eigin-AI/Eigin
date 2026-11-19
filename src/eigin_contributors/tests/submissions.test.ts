import { testDatabaseUrl } from "./database.ts";
import { before, after, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { Pool } from "pg";
import { createPool } from "../src/lib/server/database.ts";
import {
  submit,
  current,
  digest,
  acceptedAgreements,
  consentStatements,
  type Contract,
} from "../src/lib/server/submissions.ts";

const url = testDatabaseUrl();
const admin = createPool(url);
const schema = `submission_test_${randomBytes(8).toString("hex")}`;
const pool = new Pool({
  connectionString: url,
  options: `-c search_path=${schema}`,
});
const user = {
  id: "1",
  gitlabId: "123",
  username: "contributor",
  name: "Test",
};
let contract: Contract;
function form(expected = "", markdown = "# Private spec") {
  const data = new FormData();
  for (const [key, value] of Object.entries({
    email: "private@example.org",
    author: "Test Author",
    authorEmail: "public@example.org",
    acceptedCla: "on",
    acceptedTerms: "on",
    claVersion: "cla-v1",
    termsVersion: contract.terms.version,
    claHash: contract.cla.sha256,
    termsHash: contract.terms.sha256,
    expectedRevision: expected,
  }))
    data.set(key, value);
  data.set("file", new File([markdown], "spec.md"));
  return data;
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
    "TRUNCATE submission_revisions, submissions, call_contracts, agreement_snapshots, users, sessions RESTART IDENTITY CASCADE",
  );
  await pool.query(
    "INSERT INTO users (gitlab_user_id,gitlab_username,display_name) VALUES (123,'contributor','Test'), (456,'another','Another')",
  );
  const agreement = (version: string) => ({
    version,
    body: version,
    sha256: digest(version),
  });
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

test("receipt survives reload and stays scoped to its owner, with immutable consent snapshots", async () => {
  const saved = await submit(pool, user, contract, form());
  assert.deepEqual(await current(pool, user.id, contract.slug), saved);
  assert.equal(await current(pool, "2", contract.slug), null);
  const row = (
    await pool.query("SELECT consent,cla_sha256 FROM submission_revisions")
  ).rows[0];
  assert.equal(row.consent.gitlabId, user.gitlabId);
  assert.equal(row.consent.mode, "rehearsal");
  assert.equal(row.consent.cla, consentStatements.cla);
  assert.equal(row.consent.terms, "I accept the participation terms.");
  assert.equal(row.consent.acceptedAt, saved.receivedAt);
  assert.equal(row.consent.claVersion, contract.cla.version);
  assert.equal(row.consent.termsVersion, contract.terms.version);
  assert.equal(Object.hasOwn(row.consent, "individual"), false);
  const snapshots = (
    await pool.query("SELECT * FROM agreement_snapshots ORDER BY version")
  ).rows;
  assert.deepEqual(
    snapshots,
    [contract.cla, contract.terms].map(({ sha256, version, body }) => ({
      sha256,
      version,
      body,
    })),
  );
  assert.equal(row.cla_sha256, digest("cla-v1"));
});
test("replacement can retain the current file and failed stale edits preserve its successor", async () => {
  const first = await submit(pool, user, contract, form());
  const edit = form(first.id);
  edit.delete("file");
  edit.set("author", "New author");
  const next = await submit(pool, user, contract, edit);
  assert.equal(next.markdown, first.markdown);
  assert.equal(next.author, "New author");
  await assert.rejects(
    submit(pool, user, contract, form(first.id)),
    /newer revision/,
  );
  assert.equal((await current(pool, user.id, contract.slug))!.id, next.id);
  assert.equal(
    (await pool.query("SELECT * FROM submission_revisions")).rowCount,
    2,
  );
});
test("concurrent initial submissions cannot overwrite each other", async () => {
  const attempts = await Promise.allSettled([
    submit(pool, user, contract, form()),
    submit(pool, user, contract, form()),
  ]);
  assert.equal(attempts.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(
    (await pool.query("SELECT * FROM submission_revisions")).rowCount,
    1,
  );
});
test("all acceptance controls and current versions are required", async () => {
  for (const key of [
    "acceptedCla",
    "acceptedTerms",
    "claVersion",
    "termsVersion",
    "claHash",
    "termsHash",
  ]) {
    const data = form();
    data.delete(key);
    await assert.rejects(submit(pool, user, contract, data));
  }
  assert.equal(await current(pool, user.id, contract.slug), null);
});
test("invalid files and metadata cannot create a submission", async () => {
  for (const file of [
    new File([""], "empty.md"),
    new File(["x"], "wrong.txt"),
    new File([new Uint8Array([255])], "bad.md"),
    new File(["a".repeat(256 * 1024 + 1)], "big.md"),
  ]) {
    const data = form();
    data.set("file", file);
    await assert.rejects(submit(pool, user, contract, data));
  }
  const data = form();
  data.set("email", "invalid");
  await assert.rejects(submit(pool, user, contract, data));
  assert.equal(await current(pool, user.id, contract.slug), null);
});
test("closed deadlines and changed call conditions fail without losing the receipt", async () => {
  const first = await submit(pool, user, contract, form());
  await assert.rejects(
    submit(
      pool,
      user,
      { ...contract, selectedAmountMinor: 12345 },
      form(first.id),
    ),
    /conditions have changed/,
  );
  const closed = {
    ...contract,
    slug: "closed",
    opensAt: "2020-01-01T00:00:00Z",
    closesAt: "2020-01-02T00:00:00Z",
  };
  await assert.rejects(submit(pool, user, closed, form()), /closed/);
  assert.equal((await current(pool, user.id, contract.slug))!.id, first.id);
});
test("a request waiting on a lock cannot enter after the deadline", async () => {
  contract.closesAt = new Date(Date.now() + 500).toISOString();
  const first = await submit(pool, user, contract, form());
  const lock = await pool.connect();
  try {
    await lock.query("BEGIN");
    await lock.query("SELECT * FROM call_contracts FOR UPDATE");
    const pending = submit(pool, user, contract, form(first.id));
    const rejection = assert.rejects(pending, /closed/);
    await new Promise((resolve) => setTimeout(resolve, 600));
    await lock.query("COMMIT");
    await rejection;
  } finally {
    await lock.query("ROLLBACK");
    lock.release();
  }
  assert.equal((await current(pool, user.id, contract.slug))!.id, first.id);
});

test("previous acceptance is prefilled only while versions, content, and statements match", async () => {
  assert.deepEqual(acceptedAgreements(null, contract), {
    cla: false,
    terms: false,
  });
  const saved = await submit(pool, user, contract, form());
  assert.deepEqual(acceptedAgreements(saved, contract), {
    cla: true,
    terms: true,
  });
  assert.equal(
    acceptedAgreements(saved, {
      ...contract,
      terms: { ...contract.terms, version: "terms-v2" },
    }).terms,
    false,
  );
  assert.equal(
    acceptedAgreements(saved, {
      ...contract,
      cla: { ...contract.cla, sha256: digest("changed") },
    }).cla,
    false,
  );
  const changed = structuredClone(saved);
  changed.acceptance.terms.statement = "Different statement";
  assert.equal(acceptedAgreements(changed, contract).terms, false);
});

test("changed agreements preserve frozen contracts and existing consent", async () => {
  const first = await submit(pool, user, contract, form());
  const frozen = (await pool.query("SELECT * FROM call_contracts")).rows[0];
  const original = (
    await pool.query("SELECT * FROM submission_revisions WHERE id=$1", [
      first.id,
    ])
  ).rows[0];
  contract = {
    ...contract,
    terms: { version: "new-terms", body: "changed", sha256: digest("changed") },
  };
  await assert.rejects(
    submit(pool, user, contract, form(first.id)),
    /conditions have changed/,
  );
  assert.deepEqual(
    (await pool.query("SELECT * FROM call_contracts")).rows[0],
    frozen,
  );
  assert.deepEqual(
    (
      await pool.query("SELECT * FROM submission_revisions WHERE id=$1", [
        first.id,
      ])
    ).rows[0],
    original,
  );
});

test("stale agreement text cannot create a revision or acceptance evidence", async () => {
  const first = await submit(pool, user, contract, form());
  const data = form(first.id);
  contract.terms = {
    ...contract.terms,
    body: "changed terms",
    sha256: digest("changed terms"),
  };
  await assert.rejects(
    submit(pool, user, contract, data),
    /agreements changed/,
  );
  assert.equal(
    (await pool.query("SELECT * FROM submission_revisions")).rowCount,
    1,
  );
  assert.equal(
    (await pool.query("SELECT * FROM agreement_snapshots")).rowCount,
    2,
  );
  assert.equal((await current(pool, user.id, contract.slug))!.id, first.id);
});

test("a contributor cannot exceed 20 immutable revisions for a call", async () => {
  let saved = await submit(pool, user, contract, form());
  for (let i = 1; i < 20; i++)
    saved = await submit(pool, user, contract, form(saved.id));
  await assert.rejects(
    submit(pool, user, contract, form(saved.id)),
    /20 saved versions/,
  );
  assert.deepEqual(await current(pool, user.id, contract.slug), saved);
  assert.equal(
    (await pool.query("SELECT id FROM submission_revisions")).rowCount,
    20,
  );
});
