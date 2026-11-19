import { randomBytes } from "node:crypto";
import type { Pool, PoolClient } from "pg";
import type { User } from "./auth.ts";
import { isReviewer, ReviewDenied } from "./review.ts";
import { digest } from "./submissions.ts";
import {
  readDraft,
  writeDraft,
  requireDraft,
  validateCopy,
} from "./selection-drafts.ts";
import type { ResultsCopy } from "../results-copy.ts";
import { specTitle } from "../spec-title.ts";
import {
  invalidConfirmation,
  lockedContract,
  lockSession,
  recipients,
  SelectionFailure,
  type Pair,
  type SelectionSummary,
} from "./selection-store.ts";
export { SelectionFailure } from "./selection-store.ts";
export type { Pair, SelectionSummary } from "./selection-store.ts";
export type RecordedSelection = SelectionSummary & {
  confirmedByGitlabId: string;
  confirmedAt: string;
  mode: "rehearsal";
  resultsCopy: ResultsCopy | null;
  resultsVersion: string | null;
};

/** Private, irreversible selection operations for configured reviewers. */
export class Selection {
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
    user: User | null,
    run: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    this.authorize(user);
    const client = await this.pool.connect();
    let discard = false;
    try {
      await client.query("BEGIN");
      const result = await run(client);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      try {
        await client.query("ROLLBACK");
      } catch {
        discard = true;
      }
      throw error;
    } finally {
      client.release(discard);
    }
  }

  private async resolve(client: PoolClient, slug: string, pair: Pair) {
    const contract = await lockedContract(client, slug);
    const chosen = await recipients(client, slug, pair);
    return {
      contract,
      summary: {
        callSlug: slug,
        currency: contract.currency,
        selected: { ...chosen.selected, amountMinor: contract.selectedAmount },
        runnerUp: { ...chosen.runnerUp, amountMinor: contract.runnerUpAmount },
      } satisfies SelectionSummary,
    };
  }

  /** Read-only summary; taking row locks creates no decision or confirmation. */
  async summary(
    user: User | null,
    slug: string,
    pair: Pair,
  ): Promise<SelectionSummary> {
    return this.transaction(
      user,
      async (client) => (await this.resolve(client, slug, pair)).summary,
    );
  }

  /** Load the shared private editorial draft. */
  async draft(user: User | null, slug: string) {
    this.authorize(user);
    return readDraft(this.pool, slug);
  }

  /** Save provisional choices and copy without recording a final decision. */
  async saveDraft(
    user: User | null,
    sessionToken: string,
    slug: string,
    pair: Pair,
    copy: ResultsCopy,
    expectedVersion: string,
  ) {
    this.authorize(user);
    const validated = validateCopy(copy);
    return this.transaction(user, async (client) => {
      await this.resolve(client, slug, pair);
      await lockSession(client, user, sessionToken);
      return writeDraft(
        client,
        slug,
        pair,
        validated,
        expectedVersion,
        user.gitlabId,
      );
    });
  }

  /** Issue a short-lived confirmation only after the choices have been reviewed. */
  async prepare(
    user: User | null,
    sessionToken: string,
    slug: string,
    pair: Pair,
    draftVersion: string,
  ) {
    this.authorize(user);
    return this.transaction(user, async (client) => {
      const { contract, summary } = await this.resolve(client, slug, pair);
      const draft = await requireDraft(client, slug, pair, draftVersion);
      const sessionHash = await lockSession(client, user, sessionToken);
      await client.query(
        `DELETE FROM selection_confirmations WHERE call_slug=$1 AND
        (expires_at<=clock_timestamp() OR (reviewer_user_id=$2 AND session_hash=$3))`,
        [slug, user.id, sessionHash],
      );
      const token = randomBytes(32).toString("hex");
      const result = await client.query(
        `INSERT INTO selection_confirmations
        (token_hash,call_slug,reviewer_user_id,session_hash,contract_sha256,selected_submission_id,selected_revision_id,runner_up_submission_id,runner_up_revision_id,expires_at,draft_version)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,clock_timestamp()+interval '10 minutes',$10) RETURNING expires_at`,
        [
          digest(token),
          slug,
          user.id,
          sessionHash,
          contract.hash,
          pair.selected.submissionId,
          pair.selected.revisionId,
          pair.runnerUp.submissionId,
          pair.runnerUp.revisionId,
          draftVersion,
        ],
      );
      return {
        summary,
        copy: draft.copy,
        draftVersion,
        confirmationToken: token,
        expiresAt: result.rows[0].expires_at.toISOString() as string,
      };
    });
  }

  /** Atomically consume a session-bound confirmation and record the shared call decision. */
  async confirm(
    user: User | null,
    sessionToken: string,
    slug: string,
    token: string,
    confirmationText: string,
  ): Promise<void> {
    this.authorize(user);
    if (confirmationText !== "confirm")
      throw new SelectionFailure(400, "Type confirm to confirm the selection.");
    if (!/^[a-f0-9]{64}$/.test(token)) throw invalidConfirmation();
    await this.transaction(user, async (client) => {
      const contract = await lockedContract(client, slug);
      const sessionHash = await lockSession(client, user, sessionToken);
      const result = await client.query(
        `SELECT * FROM selection_confirmations WHERE token_hash=$1 AND call_slug=$2
        AND reviewer_user_id=$3 AND session_hash=$4 AND expires_at>clock_timestamp() FOR UPDATE`,
        [digest(token), slug, user.id, sessionHash],
      );
      const saved = result.rows[0];
      if (!saved || saved.contract_sha256 !== contract.hash)
        throw invalidConfirmation();
      const chosen = {
        selected: {
          submissionId: saved.selected_submission_id,
          revisionId: saved.selected_revision_id,
        },
        runnerUp: {
          submissionId: saved.runner_up_submission_id,
          revisionId: saved.runner_up_revision_id,
        },
      };
      await recipients(client, slug, chosen);
      const draft = await requireDraft(
        client,
        slug,
        chosen,
        saved.draft_version,
      );
      const inserted = await client.query(
        `INSERT INTO call_selections
        (call_slug,contract_sha256,selected_submission_id,selected_revision_id,runner_up_submission_id,runner_up_revision_id,
         selected_amount_minor,runner_up_amount_minor,currency,mode,confirmed_by_user_id,confirmed_by_gitlab_id,results_copy,results_version)
        SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,'rehearsal',$10,$11,$14,$15
        WHERE EXISTS (SELECT 1 FROM selection_confirmations WHERE token_hash=$12 AND expires_at>clock_timestamp())
        AND EXISTS (SELECT 1 FROM sessions WHERE token_hash=$13 AND expires_at>clock_timestamp())
        AND EXISTS (SELECT 1 FROM call_contracts WHERE slug=$1 AND (snapshot->>'closesAt')::timestamptz<=clock_timestamp())`,
        [
          slug,
          contract.hash,
          saved.selected_submission_id,
          saved.selected_revision_id,
          saved.runner_up_submission_id,
          saved.runner_up_revision_id,
          contract.selectedAmount,
          contract.runnerUpAmount,
          contract.currency,
          user.id,
          user.gitlabId,
          digest(token),
          sessionHash,
          JSON.stringify(draft.copy),
          draft.version,
        ],
      );
      if (!inserted.rowCount) throw invalidConfirmation();
      await client.query(
        "DELETE FROM selection_confirmations WHERE call_slug=$1",
        [slug],
      );
    });
  }

  /** Abandon this session's prepared confirmation before returning to the picker. */
  async cancel(
    user: User | null,
    sessionToken: string,
    slug: string,
    token: string,
  ): Promise<Pair | null> {
    this.authorize(user);
    return this.transaction(user, async (client) => {
      await client.query(
        "SELECT slug FROM call_contracts WHERE slug=$1 FOR UPDATE",
        [slug],
      );
      const sessionHash = await lockSession(client, user, sessionToken);
      const result = await client.query(
        `DELETE FROM selection_confirmations WHERE token_hash=$1
        AND call_slug=$2 AND reviewer_user_id=$3 AND session_hash=$4 RETURNING *`,
        [digest(token), slug, user.id, sessionHash],
      );
      const saved = result.rows[0];
      return saved
        ? {
            selected: {
              submissionId: saved.selected_submission_id,
              revisionId: saved.selected_revision_id,
            },
            runnerUp: {
              submissionId: saved.runner_up_submission_id,
              revisionId: saved.runner_up_revision_id,
            },
          }
        : null;
    });
  }

  /** Read immutable awarded revisions and the authenticated decision attribution. */
  async current(
    user: User | null,
    slug: string,
  ): Promise<RecordedSelection | null> {
    this.authorize(user);
    const result = await this.pool.query(
      `SELECT c.*,
      s.author_name AS selected_author,s.filename AS selected_filename,left(s.markdown,2048) AS selected_title,
      r.author_name AS runner_author,r.filename AS runner_filename,left(r.markdown,2048) AS runner_title
      FROM call_selections c JOIN submission_revisions s ON s.id=c.selected_revision_id
      JOIN submission_revisions r ON r.id=c.runner_up_revision_id WHERE c.call_slug=$1`,
      [slug],
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      callSlug: slug,
      currency: row.currency,
      mode: row.mode,
      resultsCopy: row.results_copy ?? null,
      resultsVersion: row.results_version ?? null,
      confirmedByGitlabId: row.confirmed_by_gitlab_id,
      confirmedAt: row.confirmed_at.toISOString(),
      selected: {
        submissionId: row.selected_submission_id,
        revisionId: row.selected_revision_id,
        author: row.selected_author,
        title: specTitle(row.selected_title, row.selected_filename),
        amountMinor: Number(row.selected_amount_minor),
      },
      runnerUp: {
        submissionId: row.runner_up_submission_id,
        revisionId: row.runner_up_revision_id,
        author: row.runner_author,
        title: specTitle(row.runner_title, row.runner_filename),
        amountMinor: Number(row.runner_up_amount_minor),
      },
    };
  }

  /** Read only a revision awarded by this call's recorded decision. */
  async awarded(
    user: User | null,
    slug: string,
    place: "selected" | "runner-up",
  ) {
    const saved = await this.current(user, slug);
    if (!saved) return null;
    const choice = place === "selected" ? saved.selected : saved.runnerUp;
    const result = await this.pool.query(
      "SELECT markdown,sha256 FROM submission_revisions WHERE submission_id=$1 AND id=$2",
      [choice.submissionId, choice.revisionId],
    );
    return {
      ...choice,
      markdown: result.rows[0].markdown as string,
      sha256: result.rows[0].sha256 as string,
    };
  }
}
