import { testDatabaseUrl } from "./database.ts";
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
const schema = `selection_test_${randomBytes(8).toString("hex")}`;
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
    "INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES (123,'author','Author'),(124,'runner','Runner'),(999,'reviewer','Reviewer'),(998,'second','Second')",
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

test("summaries and preparation do not decide; final confirmation records frozen revisions, funding and actor", async () => {
  const summary = await service.summary(reviewer, contract.slug, pair);
  assert.equal(summary.selected.title, "Author proposal");
  assert.equal(await count("selection_confirmations"), 0);
  const prepared = await ready();
  assert.equal(await count("call_selections"), 0);
  const pending = (await pool.query("SELECT * FROM selection_confirmations"))
    .rows[0];
  assert.equal(pending.token_hash, digest(prepared.confirmationToken));
  assert.notEqual(pending.token_hash, prepared.confirmationToken);
  await confirm(prepared.confirmationToken);
  const saved = (await service.current(reviewer, contract.slug))!;
  assert.deepEqual(saved.selected, {
    ...pair.selected,
    author: "Author",
    title: "Author proposal",
    amountMinor: 50000,
  });
  assert.equal(saved.runnerUp.amountMinor, 25000);
  assert.equal(saved.currency, "EUR");
  assert.deepEqual(saved.resultsCopy, copy);
  assert.equal(saved.resultsVersion, "1");
  assert.equal(saved.mode, "rehearsal");
  assert.equal(saved.confirmedByGitlabId, "999");
  assert.ok(Date.parse(saved.confirmedAt));
  assert.equal(await count("selection_confirmations"), 0);
  assert.deepEqual(await service.current(second, contract.slug), saved);
  await assert.rejects(confirm(prepared.confirmationToken), SelectionFailure);
});

test("all service entry points independently deny non-reviewers", async () => {
  for (const user of [null, author]) {
    await assert.rejects(service.draft(user, contract.slug), ReviewDenied);
    await assert.rejects(
      service.saveDraft(user, "session-a", contract.slug, pair, copy, "0"),
      ReviewDenied,
    );
    await assert.rejects(
      service.summary(user, contract.slug, pair),
      ReviewDenied,
    );
    await assert.rejects(
      service.prepare(user, "session-a", contract.slug, pair, "0"),
      ReviewDenied,
    );
    await assert.rejects(
      service.confirm(user, "session-a", contract.slug, "x", "confirm"),
      ReviewDenied,
    );
    await assert.rejects(service.current(user, contract.slug), ReviewDenied);
    await assert.rejects(
      service.cancel(user, "session-a", contract.slug, "x"),
      ReviewDenied,
    );
    await assert.rejects(
      service.awarded(user, contract.slug, "selected"),
      ReviewDenied,
    );
  }
  assert.equal(await count("call_selections"), 0);
});

test("open calls, invalid funding, duplicate recipients and wrong-call or stale IDs cannot be selected", async () => {
  await changeContract({
    closesAt: new Date(Date.now() + 60000).toISOString(),
  });
  await assert.rejects(ready(), /after the call closes/);
  await changeContract({
    closesAt: new Date(Date.now() - 1000).toISOString(),
    selectedAmountMinor: 0,
  });
  await assert.rejects(ready(), /funding conditions/);
  await changeContract({ selectedAmountMinor: 50000 });
  await assert.rejects(
    service.summary(reviewer, contract.slug, {
      selected: pair.selected,
      runnerUp: pair.selected,
    }),
    /different submissions/,
  );
  for (const id of ["0", "999999999999999999999", "invalid", "999"]) {
    await assert.rejects(
      service.summary(reviewer, contract.slug, {
        ...pair,
        selected: { ...pair.selected, submissionId: id },
      }),
      SelectionFailure,
    );
  }
  await assert.rejects(
    service.summary(reviewer, contract.slug, {
      ...pair,
      selected: { ...pair.selected, revisionId: pair.runnerUp.revisionId },
    }),
    SelectionFailure,
  );
  await pool.query("INSERT INTO call_contracts VALUES ('other',$1,$2)", [
    digest("other"),
    JSON.stringify({ ...contract, slug: "other" }),
  ]);
  await assert.rejects(
    service.summary(reviewer, "other", pair),
    SelectionFailure,
  );
  assert.equal(await count("call_selections"), 0);
});

test("confirmation text, token, call and session bindings are enforced before writing", async () => {
  const { confirmationToken: token } = await ready();
  await assert.rejects(
    service.confirm(reviewer, "session-a", contract.slug, token, "wrong"),
    /Type confirm/,
  );
  await assert.rejects(confirm("a".repeat(64)), SelectionFailure);
  await assert.rejects(
    service.confirm(reviewer, "other-session", contract.slug, token, "confirm"),
    SelectionFailure,
  );
  await assert.rejects(
    service.confirm(second, "session-b", contract.slug, token, "confirm"),
    SelectionFailure,
  );
  await pool.query("INSERT INTO call_contracts VALUES ('other',$1,$2)", [
    digest("other"),
    JSON.stringify({ ...contract, slug: "other" }),
  ]);
  await assert.rejects(
    service.confirm(reviewer, "session-a", "other", token, "confirm"),
    SelectionFailure,
  );
  assert.equal(await count("call_selections"), 0);
  await confirm(token);
});

test("expired confirmations, expired sessions and logout invalidate final confirmation", async () => {
  const first = await ready();
  await pool.query(
    "UPDATE selection_confirmations SET expires_at=clock_timestamp()-interval '1 second'",
  );
  await assert.rejects(confirm(first.confirmationToken), SelectionFailure);
  const next = await ready();
  await pool.query(
    "UPDATE sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE token_hash=$1",
    [digest("session-a")],
  );
  await assert.rejects(confirm(next.confirmationToken), SelectionFailure);
  await pool.query("DELETE FROM sessions WHERE token_hash=$1", [
    digest("session-a"),
  ]);
  assert.equal(await count("selection_confirmations"), 0);
  await assert.rejects(ready(), SelectionFailure);
});

test("changed contracts or current revisions require a new review", async () => {
  const prepared = await ready();
  await changeContract({ runnerUpAmountMinor: 26000 });
  await assert.rejects(confirm(prepared.confirmationToken), SelectionFailure);
  const next = await ready();
  await pool.query(
    "UPDATE submissions SET current_revision_id=NULL WHERE id=$1",
    [pair.selected.submissionId],
  );
  await assert.rejects(confirm(next.confirmationToken), SelectionFailure);
  assert.equal(await count("call_selections"), 0);
});

test("concurrent reviewers produce one shared decision and never overwrite it", async () => {
  const a = await ready();
  const b = await service.prepare(
    second,
    "session-b",
    contract.slug,
    pair,
    (await service.draft(second, contract.slug))!.version,
  );
  const results = await Promise.allSettled([
    confirm(a.confirmationToken),
    service.confirm(
      second,
      "session-b",
      contract.slug,
      b.confirmationToken,
      "confirm",
    ),
  ]);
  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(await count("call_selections"), 1);
  assert.equal(await count("selection_confirmations"), 0);
  await assert.rejects(ready(), /already been recorded/);
});

test("failed writes roll back both decision and confirmation consumption", async () => {
  const prepared = await ready();
  await pool.query(
    "ALTER TABLE call_selections ADD CONSTRAINT injected_failure CHECK (false)",
  );
  try {
    await assert.rejects(confirm(prepared.confirmationToken));
  } finally {
    await pool.query(
      "ALTER TABLE call_selections DROP CONSTRAINT injected_failure",
    );
  }
  assert.equal(await count("call_selections"), 0);
  assert.equal(await count("selection_confirmations"), 1);
  await confirm(prepared.confirmationToken);
});

test("recorded reading remains pinned to the awarded revision", async () => {
  const prepared = await ready();
  await confirm(prepared.confirmationToken);
  await pool.query(
    "UPDATE submissions SET current_revision_id=NULL WHERE id=$1",
    [pair.selected.submissionId],
  );
  const awarded = (await service.awarded(reviewer, contract.slug, "selected"))!;
  assert.equal(awarded.revisionId, pair.selected.revisionId);
  assert.match(awarded.markdown, /# Author proposal/);
  assert.equal(await service.awarded(reviewer, "missing", "selected"), null);
});

test("returning to choices revokes only that session's prepared confirmation", async () => {
  const prepared = await ready();
  assert.equal(
    await service.cancel(
      second,
      "session-b",
      contract.slug,
      prepared.confirmationToken,
    ),
    null,
  );
  assert.equal(await count("selection_confirmations"), 1);
  assert.deepEqual(
    await service.cancel(
      reviewer,
      "session-a",
      contract.slug,
      prepared.confirmationToken,
    ),
    pair,
  );
  await assert.rejects(confirm(prepared.confirmationToken), SelectionFailure);
  assert.equal(await count("call_selections"), 0);
});

test("the deadline is checked after waiting for the submission call lock", async () => {
  await changeContract({ closesAt: new Date(Date.now() + 500).toISOString() });
  const blocker = await pool.connect();
  let prepared: ReturnType<typeof ready> | undefined;
  try {
    await blocker.query("BEGIN");
    await blocker.query(
      "SELECT slug FROM call_contracts WHERE slug=$1 FOR UPDATE",
      [contract.slug],
    );
    prepared = ready();
    await blocker.query("SELECT pg_sleep(0.7)");
    await blocker.query("COMMIT");
    assert.ok((await prepared).confirmationToken);
    assert.equal(await count("call_selections"), 0);
  } finally {
    await blocker.query("ROLLBACK");
    blocker.release();
    await prepared?.catch(() => {});
  }
});

test("drafts save incomplete copy privately but preview requires every editorial field", async () => {
  const incomplete = { ...copy, learned: "" };
  const version = await service.saveDraft(
    reviewer,
    "session-a",
    contract.slug,
    pair,
    incomplete,
    "0",
  );
  assert.deepEqual(
    (await service.draft(second, contract.slug))!.copy,
    incomplete,
  );
  await assert.rejects(
    service.prepare(reviewer, "session-a", contract.slug, pair, version),
    /what we learned/,
  );
  assert.equal(await count("call_selections"), 0);
  assert.equal(await count("selection_confirmations"), 0);
  await assert.rejects(
    service.saveDraft(
      reviewer,
      "session-a",
      contract.slug,
      pair,
      { ...copy, introduction: "x".repeat(1201) },
      version,
    ),
    SelectionFailure,
  );
});

test("stale editorial writes never overwrite a shared draft", async () => {
  await service.saveDraft(
    reviewer,
    "session-a",
    contract.slug,
    pair,
    copy,
    "0",
  );
  const next = { ...copy, learned: "Updated by another reviewer." };
  await service.saveDraft(second, "session-b", contract.slug, pair, next, "1");
  await assert.rejects(
    service.saveDraft(reviewer, "session-a", contract.slug, pair, copy, "1"),
    /draft changed/,
  );
  assert.deepEqual((await service.draft(reviewer, contract.slug))!.copy, next);
});

test("editing results invalidates all pending previews and freezes the confirmed copy", async () => {
  const first = await ready();
  const next = { ...copy, selectedSummary: "Revised description." };
  const version = await service.saveDraft(
    second,
    "session-b",
    contract.slug,
    pair,
    next,
    "1",
  );
  await assert.rejects(confirm(first.confirmationToken), SelectionFailure);
  await assert.rejects(
    service.prepare(reviewer, "session-a", contract.slug, pair, "1"),
    SelectionFailure,
  );
  const preview = await service.prepare(
    reviewer,
    "session-a",
    contract.slug,
    pair,
    version,
  );
  assert.deepEqual(preview.copy, next);
  await confirm(preview.confirmationToken);
  await assert.rejects(
    service.saveDraft(second, "session-b", contract.slug, pair, copy, version),
    /already been recorded/,
  );
  assert.deepEqual(
    (await service.current(reviewer, contract.slug))!.resultsCopy,
    next,
  );
});

test("a preview cannot substitute different recipients for the saved draft", async () => {
  await ready();
  await assert.rejects(
    service.prepare(
      reviewer,
      "session-a",
      contract.slug,
      { selected: pair.runnerUp, runnerUp: pair.selected },
      "1",
    ),
    SelectionFailure,
  );
});
