import { createPool } from "../src/lib/server/database.ts";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL is required");
const pool = createPool(url);
try {
  await pool.query(
    "DELETE FROM oauth_attempts WHERE expires_at <= statement_timestamp()",
  );
} finally {
  await pool.end();
}
