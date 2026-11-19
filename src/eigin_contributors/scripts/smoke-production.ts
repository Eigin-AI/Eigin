import { checkPublication } from "./smoke-publication.ts";
import { testDatabaseUrl } from "../tests/database.ts";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createPool } from "../src/lib/server/database.ts";
import { digest } from "../src/lib/server/submissions.ts";

const pool = createPool(testDatabaseUrl());
const token = randomBytes(32).toString("base64url");
const gitlabId = "5";
const canonical = "https://contributors.example.invalid";
const base = "http://127.0.0.1:5376";
let userId: string | undefined;
let server: ReturnType<typeof spawn> | undefined;
try {
  userId = (
    await pool.query(
      "INSERT INTO users(gitlab_user_id,gitlab_username,display_name) VALUES ($1,$2,'Synthetic production smoke reviewer') RETURNING id",
      [gitlabId, `production-smoke-${randomBytes(8).toString("hex")}`],
    )
  ).rows[0].id;
  await pool.query(
    "INSERT INTO sessions VALUES ($1,$2,clock_timestamp()+interval '10 minutes')",
    [digest(token), userId],
  );
  server = spawn(process.execPath, ["build/index.js"], {
    stdio: "ignore",
    env: {
      ...process.env,
      NODE_ENV: "production",
      HOST: "127.0.0.1",
      PORT: "5376",
      ORIGIN: canonical,
      DATABASE_URL: testDatabaseUrl(),
      GITLAB_CLIENT_ID: "synthetic-smoke",
      GITLAB_CLIENT_SECRET: "synthetic-smoke",
      REVIEWER_GITLAB_IDS: gitlabId,
    },
  });
  const headers = {
    Cookie: `contributors_session=${token}`,
    Origin: canonical,
  };
  let ready = false;
  for (let i = 0; i < 100; i++) {
    if (server.exitCode !== null)
      throw new Error("Built server exited before startup.");
    try {
      if ((await fetch(base + "/account", { headers })).status === 200) {
        ready = true;
        break;
      }
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.ok(
    ready,
    "Built server must accept the valid synthetic reviewer session.",
  );
  const home = await fetch(base + "/", { headers });
  assert.equal(home.status, 200);
  assert.ok(!(await home.text()).includes("Demo: choosing funded specs"));
  for (const path of [
    "/calls/tool-safety",
    "/guides/participation-terms",
    "/calls/tool-safety/submission",
    "/review",
    "/review/calls/tool-safety",
  ]) {
    assert.equal((await fetch(base + path, { headers })).status, 200, path);
  }
  assert.equal((await fetch(base + "/review")).status, 404);
  for (const path of [
    "/calls/unknown-call",
    "/%63alls/unknown-call",
    "/%63alls/unknown-call/__data.json",
    "/calls/local%2Dmemory",
    "/%63alls/local-memory/__data.json",
    "/%72eview/calls/unknown-call/selection/publish",
    "/calls/unknown-call/__data.json",
    "/calls/unknown-call/specs/selected",
    "/calls/unknown-call/specs/runner-up",
    "/review/calls/unknown-call/selection/publish",
  ]) {
    const response = await fetch(base + path, { headers });
    assert.equal(response.status, 404, path);
    assert.match(response.headers.get("cache-control") ?? "", /no-store/, path);
  }
  for (const action of ["prepare", "publish", "cancel"]) {
    const response = await fetch(
      base + "/%72eview/calls/unknown-call/selection/publish?/" + action,
      {
        method: "POST",
        headers,
        body: new URLSearchParams({ confirmationText: "publish" }),
      },
    );
    assert.equal(response.status, 404, action);
  }
  await checkPublication(pool, base, headers);
  await pool.query("UPDATE users SET gitlab_user_id=$1 WHERE id=$2", [
    "8600000000000099",
    userId,
  ]);
  assert.equal((await fetch(base + "/account", { headers })).status, 200);
  assert.equal(
    (await fetch(base + "/review/calls/tool-safety", { headers })).status,
    404,
  );
  console.log(
    "Production launch passed: public brief, private reviewer access and rehearsal isolation.",
  );
} finally {
  if (server && server.exitCode === null && server.signalCode === null) {
    const exited = once(server, "exit");
    server.kill("SIGTERM");
    await exited;
  }
  await pool.end();
}
