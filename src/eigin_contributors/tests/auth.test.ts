import { testDatabaseUrl } from "./database.ts";
import { after, before, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash, randomBytes } from "node:crypto";
import { Pool } from "pg";
import { Auth, AuthFailure, safeReturnTo } from "../src/lib/server/auth.ts";
import { createPool } from "../src/lib/server/database.ts";

const url = testDatabaseUrl();
const admin = createPool(url);
const schema = `auth_test_${randomBytes(8).toString("hex")}`;
const pool = new Pool({
  connectionString: url,
  options: `-c search_path=${schema}`,
  max: 3,
});
const config = {
  origin: "http://localhost:5176",
  clientId: "test-client",
  clientSecret: "test-secret",
};
let requestCount = 0;
let failProvider = false;
let invalidProfile = false;
let challenge = "";
let emailFields: Record<string, string> = {};
const provider: typeof fetch = async (input, init) => {
  requestCount++;
  if (failProvider) return new Response("unavailable", { status: 503 });
  if (String(input).endsWith("/oauth/token")) {
    const body = init!.body as URLSearchParams;
    assert.equal(body.get("client_id"), config.clientId);
    assert.equal(body.get("redirect_uri"), `${config.origin}/auth/callback`);
    assert.equal(
      createHash("sha256")
        .update(body.get("code_verifier")!)
        .digest("base64url"),
      challenge,
    );
    return Response.json({ access_token: "provider-token" });
  }
  assert.equal(String(input), "https://code.eigin.ai/api/v4/user");
  assert.equal(
    (init!.headers as Record<string, string>).Authorization,
    "Bearer provider-token",
  );
  return Response.json({
    id: invalidProfile ? "123" : 123,
    username: "contributor",
    name: "Test Contributor",
    ...emailFields,
  });
};
const auth = new Auth(pool, config, provider);
async function begin() {
  const attempt = await auth.begin();
  const url = new URL(attempt.url);
  challenge = url.searchParams.get("code_challenge")!;
  return { ...attempt, state: url.searchParams.get("state")! };
}
before(async () => {
  await admin.query(`CREATE SCHEMA ${schema}`);
  await pool.query(
    await readFile(
      new URL("../migrations/001_auth.sql", import.meta.url),
      "utf8",
    ),
  );
  await pool.query(
    await readFile(
      new URL("../migrations/003_profile_author_email.sql", import.meta.url),
      "utf8",
    ),
  );
  await pool.query(
    await readFile(
      new URL("../migrations/004_oauth_destination.sql", import.meta.url),
      "utf8",
    ),
  );
});
beforeEach(async () => {
  emailFields = {};
  await pool.query(
    "TRUNCATE sessions, oauth_attempts, users RESTART IDENTITY CASCADE",
  );
  requestCount = 0;
  failProvider = false;
  invalidProfile = false;
});
after(async () => {
  await pool.end();
  await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
  await admin.end();
});

test("login uses fixed provider, state and S256; stores only hashed session and returns stable identity", async () => {
  const attempt = await begin();
  const url = new URL(attempt.url);
  assert.equal(url.origin, "https://code.eigin.ai");
  assert.equal(url.searchParams.get("scope"), "read_user");
  assert.equal(url.searchParams.get("code_challenge_method"), "S256");
  const { token } = await auth.complete(
    attempt.binding,
    attempt.state,
    "authorization-code",
  );
  assert.deepEqual(await auth.user(token), {
    id: "1",
    gitlabId: "123",
    username: "contributor",
    name: "Test Contributor",
    authorEmail: null,
  });
  const rows = (await pool.query("SELECT token_hash FROM sessions")).rows;
  assert.equal(
    rows[0].token_hash,
    createHash("sha256").update(token).digest("hex"),
  );
  assert.notEqual(rows[0].token_hash, token);
  assert.equal((await pool.query("SELECT * FROM oauth_attempts")).rowCount, 0);
  await auth.logout(token);
  assert.equal(await auth.user(token), null);
});

test("missing binding, wrong state and expired callbacks cannot call the provider", async () => {
  const a = await begin();
  await assert.rejects(auth.complete(undefined, a.state, "code"), AuthFailure);
  await assert.rejects(
    auth.complete(a.binding, randomBytes(32).toString("base64url"), "code"),
    AuthFailure,
  );
  await pool.query(
    "UPDATE oauth_attempts SET expires_at = clock_timestamp() - interval '1 second'",
  );
  await assert.rejects(auth.complete(a.binding, a.state, "code"), AuthFailure);
  assert.equal(requestCount, 0);
});

test("concurrent callback replay issues one session only", async () => {
  const a = await begin();
  const results = await Promise.allSettled([
    auth.complete(a.binding, a.state, "code"),
    auth.complete(a.binding, a.state, "code"),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal((await pool.query("SELECT * FROM sessions")).rowCount, 1);
});

test("provider failure consumes callback and creates no session", async () => {
  const a = await begin();
  failProvider = true;
  await assert.rejects(auth.complete(a.binding, a.state, "code"), AuthFailure);
  failProvider = false;
  await assert.rejects(auth.complete(a.binding, a.state, "code"), AuthFailure);
  assert.equal((await pool.query("SELECT * FROM sessions")).rowCount, 0);
});

test("malformed provider identity never becomes an account", async () => {
  const a = await begin();
  invalidProfile = true;
  await assert.rejects(auth.complete(a.binding, a.state, "code"), AuthFailure);
  assert.equal((await pool.query("SELECT * FROM users")).rowCount, 0);
});

test("session expiry and forged tokens fail closed", async () => {
  const a = await begin();
  const { token } = await auth.complete(a.binding, a.state, "code");
  assert.equal(await auth.user("forged"), null);
  assert.equal(await auth.user(randomBytes(32).toString("base64url")), null);
  await pool.query(
    "UPDATE sessions SET expires_at = clock_timestamp() - interval '1 second'",
  );
  assert.equal(await auth.user(token), null);
});

test("author email uses the commit preference or public fallback without exposing private contact email", async () => {
  for (const [fields, expected] of [
    [
      {
        commit_email: "commit@example.org",
        public_email: "public@example.org",
      },
      "commit@example.org",
    ],
    [{ public_email: "public@example.org" }, "public@example.org"],
    [{ commit_email: "_private", public_email: "public@example.org" }, null],
    [{ email: "private@example.org" }, null],
    [{ commit_email: "invalid", public_email: "invalid" }, null],
  ] as [Record<string, string>, string | null][]) {
    emailFields = fields;
    const a = await begin();
    const { token } = await auth.complete(a.binding, a.state, "code");
    assert.equal((await auth.user(token))!.authorEmail, expected);
    await auth.logout(token);
  }
});

test("OAuth resumes the requested submission, with unsafe destinations rejected", async () => {
  for (const destination of [
    "/",
    "/#open-calls",
    "/calls/tool-safety",
    "/guides/process",
    "/guides/participation-terms",
    "/guides/participation-terms#payment",
    "/calls/another-call/submission?edit=1",
    "/review/calls/another-call/submissions/123",
    "/calls/tool-safety/submission",
    "/calls/tool-safety/submission?edit=1",
  ]) {
    const attempt = await auth.begin(destination);
    const url = new URL(attempt.url);
    challenge = url.searchParams.get("code_challenge")!;
    const login = await auth.complete(
      attempt.binding,
      url.searchParams.get("state"),
      "code",
    );
    assert.equal(login.returnTo, destination);
    await auth.logout(login.token);
  }
  for (const value of [
    "https://evil.example",
    "//evil.example",
    "/\\evil.example",
    "/auth/logout",
    "/%2f%2fevil.example",
    "/guides/rehearsal-terms",
    "/auth/callback",
    "/calls/tool-safety/submission/download",
  ]) {
    assert.equal(safeReturnTo(value), "/");
  }
});
