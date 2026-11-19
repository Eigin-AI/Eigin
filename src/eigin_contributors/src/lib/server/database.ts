import { Pool } from "pg";

/** Create a bounded pool without logging credentials. */
export function createPool(url: string) {
  return new Pool({
    connectionString: url,
    max: 5,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 10000,
  });
}
