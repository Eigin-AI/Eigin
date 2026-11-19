import type { Pool, PoolClient } from "pg";
import type { Pair } from "./selection-store.ts";
import { SelectionFailure } from "./selection-store.ts";
import { resultsFields, type ResultsCopy } from "../results-copy.ts";

export type ResultsDraft = {
  pair: Pair;
  copy: ResultsCopy;
  version: string;
  updatedByGitlabId: string;
  updatedAt: string;
};

/** Bound editorial text and optionally require publication-ready content. */
export function validateCopy(copy: ResultsCopy, complete = false): ResultsCopy {
  const result = {} as ResultsCopy;
  for (const { key, label, limit } of resultsFields) {
    const value = copy?.[key];
    if (
      typeof value !== "string" ||
      value.length > limit ||
      value.includes("\0")
    )
      throw new SelectionFailure(
        400,
        `${label} must be plain text of at most ${limit} characters.`,
      );
    if (complete && !value.trim())
      throw new SelectionFailure(
        400,
        `Add ${label.toLowerCase()} before previewing the results.`,
      );
    result[key] = value;
  }
  return result;
}

/** Read only the shared private draft and its edit version. */
export async function readDraft(
  db: Pool | PoolClient,
  slug: string,
): Promise<ResultsDraft | null> {
  const {
    rows: [row],
  } = await db.query("SELECT * FROM selection_drafts WHERE call_slug=$1", [
    slug,
  ]);
  return row
    ? {
        pair: {
          selected: {
            submissionId: row.selected_submission_id,
            revisionId: row.selected_revision_id,
          },
          runnerUp: {
            submissionId: row.runner_up_submission_id,
            revisionId: row.runner_up_revision_id,
          },
        },
        copy: row.copy,
        version: row.version,
        updatedByGitlabId: row.updated_by_gitlab_id,
        updatedAt: row.updated_at.toISOString(),
      }
    : null;
}

/** Save under the already-held call lock, rejecting edits based on an old draft. */
export async function writeDraft(
  client: PoolClient,
  slug: string,
  pair: Pair,
  copy: ResultsCopy,
  expected: string,
  gitlabId: string,
) {
  const current = await readDraft(client, slug);
  if ((current?.version ?? "0") !== expected)
    throw new SelectionFailure(
      409,
      "The results draft changed in another tab or reviewer session. Your text is still shown below; copy it before reloading the saved draft.",
    );
  const version = String(BigInt(current?.version ?? "0") + 1n);
  await client.query(
    `INSERT INTO selection_drafts
    (call_slug,version,selected_submission_id,selected_revision_id,runner_up_submission_id,runner_up_revision_id,copy,updated_by_gitlab_id)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(call_slug) DO UPDATE SET
    version=EXCLUDED.version,selected_submission_id=EXCLUDED.selected_submission_id,selected_revision_id=EXCLUDED.selected_revision_id,
    runner_up_submission_id=EXCLUDED.runner_up_submission_id,runner_up_revision_id=EXCLUDED.runner_up_revision_id,
    copy=EXCLUDED.copy,updated_by_gitlab_id=EXCLUDED.updated_by_gitlab_id,updated_at=clock_timestamp()`,
    [
      slug,
      version,
      pair.selected.submissionId,
      pair.selected.revisionId,
      pair.runnerUp.submissionId,
      pair.runnerUp.revisionId,
      JSON.stringify(copy),
      gitlabId,
    ],
  );
  await client.query("DELETE FROM selection_confirmations WHERE call_slug=$1", [
    slug,
  ]);
  return version;
}

/** Bind the final preview to the saved pair and exact editorial version. */
export async function requireDraft(
  client: PoolClient,
  slug: string,
  pair: Pair,
  version: string,
) {
  const draft = await readDraft(client, slug);
  if (
    !draft ||
    draft.version !== version ||
    draft.pair.selected.submissionId !== pair.selected.submissionId ||
    draft.pair.selected.revisionId !== pair.selected.revisionId ||
    draft.pair.runnerUp.submissionId !== pair.runnerUp.submissionId ||
    draft.pair.runnerUp.revisionId !== pair.runnerUp.revisionId
  )
    throw new SelectionFailure(
      409,
      "The results draft changed. Open the saved draft and preview it again.",
    );
  validateCopy(draft.copy, true);
  return draft;
}
