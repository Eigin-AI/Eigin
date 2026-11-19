import assert from "node:assert/strict";
import type { Pool } from "pg";
import {
  digest,
  submit,
  type Contract,
} from "../src/lib/server/submissions.ts";

/** Exercise selection and publication through the production server using disposable records. */
export async function checkPublication(
  pool: Pool,
  base: string,
  headers: Record<string, string>,
) {
  const slug = "tool-safety";
  const agreement = {
    version: "smoke",
    body: "smoke",
    sha256: digest("smoke"),
  };
  const contract: Contract = {
    slug,
    mode: "production",
    opensAt: new Date(Date.now() - 60000).toISOString(),
    closesAt: new Date(Date.now() + 3600000).toISOString(),
    selectedAmountMinor: 50000,
    runnerUpAmountMinor: 25000,
    currency: "EUR",
    cla: agreement,
    terms: agreement,
  };
  const choices: string[] = [];
  for (let i = 0; i < 3; i++) {
    const name = `Smoke author ${i}`,
      gitlabId = String(810000 + i);
    const {
      rows: [user],
    } = await pool.query(
      "INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES ($1,$2,$2) RETURNING id",
      [gitlabId, name],
    );
    const form = new FormData();
    for (const [k, v] of Object.entries({
      author: name,
      email: "private@example.invalid",
      authorEmail: "credit@example.invalid",
      acceptedCla: "on",
      acceptedTerms: "on",
      claVersion: "smoke",
      termsVersion: "smoke",
      claHash: agreement.sha256,
      termsHash: agreement.sha256,
    }))
      form.set(k, v);
    form.set(
      "file",
      new File([`# Smoke proposal ${i}\n\nPrivate text ${i}.`], "spec.md"),
    );
    const revision = await submit(
      pool,
      { id: user.id, gitlabId, username: name, name },
      contract,
      form,
    );
    const {
      rows: [s],
    } = await pool.query(
      "SELECT submission_id FROM submission_revisions WHERE id=$1",
      [revision.id],
    );
    choices.push(`${s.submission_id}:${revision.id}`);
  }
  const home = await (await fetch(base + "/")).text();
  assert.match(home, /href="\/calls\/tool-safety"/);
  assert.ok(!home.includes("Demo: choosing funded specs"));
  contract.closesAt = new Date(Date.now() - 1000).toISOString();
  await pool.query(
    "UPDATE call_contracts SET snapshot=$1, sha256=$2 WHERE slug=$3",
    [JSON.stringify(contract), digest(JSON.stringify(contract)), slug],
  );
  const selection = `${base}/review/calls/${slug}/selection`;
  const post = (path: string, values: Record<string, string>) =>
    fetch(selection + path, {
      method: "POST",
      headers: { ...headers, Accept: "text/html" },
      body: new URLSearchParams(values),
      redirect: "manual",
    });
  async function token(response: Response) {
    assert.equal(response.status, 200);
    const match = (await response.text()).match(
      /name="confirmationToken"\s+value="([a-f0-9]{64})"/,
    );
    assert.ok(match, "expected reviewer confirmation form");
    return match[1];
  }
  const confirmationToken = await token(
    await post("?/preview", {
      selected: choices[0],
      runnerUp: choices[1],
      draftVersion: "0",
      introduction: "Two useful approaches.",
      selectedSummary: "Selected approach.",
      runnerUpSummary: "Runner-up approach.",
      learned: "Useful evidence.",
    }),
  );
  assert.equal(
    (
      await post("?/confirm", {
        confirmationToken,
        confirmationText: "confirm",
      })
    ).status,
    303,
  );
  const spec = `${base}/calls/${slug}/specs/`;
  for (const place of ["selected", "runner-up"])
    assert.equal((await fetch(spec + place)).status, 404);
  const publishToken = await token(
    await post("/publish?/prepare", { intent: "preview-publication" }),
  );
  assert.equal(
    (
      await post("/publish?/publish", {
        confirmationToken: publishToken,
        confirmationText: "publish",
      })
    ).status,
    303,
  );
  for (const [i, place] of ["selected", "runner-up"].entries()) {
    const response = await fetch(spec + place);
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.ok(text.includes(`Private text ${i}.`));
    assert.ok(
      !text.includes("Private text 2.") &&
        !text.includes("private@example.invalid"),
    );
  }
  assert.equal((await fetch(spec + choices[2].split(":")[1])).status, 404);
  // A rehearsal snapshot for the same slug must never replace production content.
  const demo = "Seeded rehearsal publication";
  await pool.query(
    "UPDATE call_publications SET mode='rehearsal', public_snapshot=jsonb_set(public_snapshot,'{title}',to_jsonb($2::text)) WHERE call_slug=$1",
    [slug, demo],
  );
  for (const path of ["/", `/calls/${slug}`]) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.ok(!html.includes(demo));
    assert.ok(html.includes("Local detection of malicious instructions"));
  }
  assert.equal((await fetch(spec + "selected")).status, 404);
}
