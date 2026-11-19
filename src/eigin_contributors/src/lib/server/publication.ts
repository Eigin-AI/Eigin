import { randomBytes } from "node:crypto";
import type { Pool, PoolClient } from "pg";
import type { User } from "./auth.ts";
import type { PublicCall } from "../publication.ts";
import { isReviewer, ReviewDenied } from "./review.ts";
import { digest } from "./submissions.ts";
import { lockSession, SelectionFailure } from "./selection-store.ts";
import { publicationSnapshot } from "./publication-snapshot.ts";

const unavailable = () =>
  new SelectionFailure(
    409,
    "This publication confirmation is unavailable or expired. Preview the results again.",
  );

/** Explicit reviewer approval is the only operation that creates public results. */
export class Publication {
  private pool: Pool;
  private configured: string | undefined;
  constructor(pool: Pool, configured: string | undefined) {
    this.pool = pool;
    this.configured = configured;
  }
  private authorize(user: User | null): asserts user is User {
    if (!isReviewer(user, this.configured)) throw new ReviewDenied("Not found");
  }
  private async transaction<T>(
    run: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    const client = await this.pool.connect();
    let discard = false;
    try {
      await client.query("BEGIN");
      const value = await run(client);
      await client.query("COMMIT");
      return value;
    } catch (e) {
      try {
        await client.query("ROLLBACK");
      } catch {
        discard = true;
      }
      throw e;
    } finally {
      client.release(discard);
    }
  }
  /** Bind a ten-minute confirmation to the exact public preview and current session. */
  async prepare(
    user: User | null,
    session: string,
    slug: string,
    call: PublicCall | null,
  ) {
    this.authorize(user);
    return this.transaction(async (client) => {
      const preview = await publicationSnapshot(client, slug, call);
      const hash = await lockSession(client, user, session);
      await client.query(
        `DELETE FROM publication_confirmations WHERE call_slug=$1 AND
        (expires_at<=clock_timestamp() OR (reviewer_user_id=$2 AND session_hash=$3))`,
        [slug, user.id, hash],
      );
      const token = randomBytes(32).toString("hex");
      const {
        rows: [row],
      } = await client.query(
        `INSERT INTO publication_confirmations
        (token_hash,call_slug,reviewer_user_id,session_hash,snapshot_sha256,expires_at)
        VALUES ($1,$2,$3,$4,$5,clock_timestamp()+interval '10 minutes') RETURNING expires_at`,
        [digest(token), slug, user.id, hash, digest(JSON.stringify(preview))],
      );
      return {
        preview,
        confirmationToken: token,
        expiresAt: row.expires_at.toISOString() as string,
      };
    });
  }
  /** Publish the recorded pair and copy atomically without accepting browser-supplied content. */
  async publish(
    user: User | null,
    session: string,
    slug: string,
    call: PublicCall | null,
    token: string,
    text: string,
  ): Promise<void> {
    this.authorize(user);
    if (text !== "publish")
      throw new SelectionFailure(400, "Type publish to publish the results.");
    if (!/^[a-f0-9]{64}$/.test(token)) throw unavailable();
    await this.transaction(async (client) => {
      const snapshot = await publicationSnapshot(client, slug, call);
      const sessionHash = await lockSession(client, user, session);
      const sha = digest(JSON.stringify(snapshot));
      const {
        rows: [confirmation],
      } = await client.query(
        `SELECT snapshot_sha256 FROM publication_confirmations
        WHERE token_hash=$1 AND call_slug=$2 AND reviewer_user_id=$3 AND session_hash=$4
        AND expires_at>clock_timestamp() FOR UPDATE`,
        [digest(token), slug, user.id, sessionHash],
      );
      if (!confirmation || confirmation.snapshot_sha256 !== sha)
        throw unavailable();
      const result = await client.query(
        `INSERT INTO call_publications
        (call_slug,public_snapshot,snapshot_sha256,published_by_user_id,published_by_gitlab_id,mode)
        SELECT $1,$2,$3,$4,$5,(SELECT mode FROM call_selections WHERE call_slug=$1)
        WHERE EXISTS (SELECT 1 FROM publication_confirmations WHERE token_hash=$6 AND expires_at>clock_timestamp())
        AND EXISTS (SELECT 1 FROM sessions WHERE token_hash=$7 AND expires_at>clock_timestamp())`,
        [
          slug,
          JSON.stringify(snapshot),
          sha,
          user.id,
          user.gitlabId,
          digest(token),
          sessionHash,
        ],
      );
      if (!result.rowCount) throw unavailable();
      await client.query(
        "DELETE FROM publication_confirmations WHERE call_slug=$1",
        [slug],
      );
    });
  }
  /** Revoke this session's pending publication without changing public visibility. */
  async cancel(
    user: User | null,
    session: string,
    slug: string,
    token: string,
  ): Promise<void> {
    this.authorize(user);
    await this.transaction(async (client) => {
      await client.query(
        "SELECT slug FROM call_contracts WHERE slug=$1 FOR UPDATE",
        [slug],
      );
      const hash = await lockSession(client, user, session);
      await client.query(
        `DELETE FROM publication_confirmations
        WHERE token_hash=$1 AND call_slug=$2 AND reviewer_user_id=$3 AND session_hash=$4`,
        [digest(token), slug, user.id, hash],
      );
    });
  }
  /** Report publication timing in private review without retrieving the public bodies. */
  async status(user: User | null, slug: string) {
    this.authorize(user);
    const {
      rows: [row],
    } = await this.pool.query(
      "SELECT published_at FROM call_publications WHERE call_slug=$1",
      [slug],
    );
    return row
      ? { publishedAt: row.published_at.toISOString() as string }
      : null;
  }
}
