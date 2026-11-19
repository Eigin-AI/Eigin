import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { createPool } from "../src/lib/server/database.ts";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL is required");
const pool = createPool(url);
const client = await pool.connect();
try {
  await client.query("BEGIN");
  await client.query("SELECT pg_advisory_xact_lock(417001)");
  await client.query(
    "CREATE TABLE IF NOT EXISTS migrations (name text PRIMARY KEY, sha256 text NOT NULL)",
  );
  const dir = new URL("../migrations/", import.meta.url);
  for (const name of (await readdir(dir))
    .filter((n) => /^\d+.*\.sql$/.test(n))
    .sort()) {
    const sql = await readFile(new URL(name, dir), "utf8");
    const hash = createHash("sha256").update(sql).digest("hex");
    const applied = await client.query(
      "SELECT sha256 FROM migrations WHERE name = $1",
      [name],
    );
    if (applied.rowCount) {
      if (applied.rows[0].sha256 !== hash)
        throw new Error(`Applied migration changed: ${name}`);
      continue;
    }
    await client.query(sql);
    await client.query("INSERT INTO migrations VALUES ($1, $2)", [name, hash]);
    console.log(`Applied ${name}`);
  }
  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
  await pool.end();
}
