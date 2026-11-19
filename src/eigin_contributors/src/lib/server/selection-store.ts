import type { PoolClient } from "pg";
import type { User } from "./auth.ts";
import { digest } from "./submissions.ts";
import { specTitle } from "../spec-title.ts";

export type Choice = { submissionId: string; revisionId: string };
export type Pair = { selected: Choice; runnerUp: Choice };
export type Recipient = Choice & {
  author: string;
  title: string;
  amountMinor: number;
};
export type SelectionSummary = {
  callSlug: string;
  selected: Recipient;
  runnerUp: Recipient;
  currency: string;
};
export class SelectionFailure extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}
export const invalidConfirmation = () =>
  new SelectionFailure(
    409,
    "This confirmation is unavailable or expired. Review your choices again.",
  );

/** Parse only positive PostgreSQL bigint identifiers. */
export function validId(value: string) {
  return /^[1-9]\d{0,18}$/.test(value) && BigInt(value) <= 9223372036854775807n;
}

/** Lock the same call row used by submission writes and read its frozen terms. */
export async function lockedContract(client: PoolClient, slug: string) {
  const result = await client.query(
    `SELECT sha256,snapshot
     FROM call_contracts WHERE slug=$1 FOR UPDATE`,
    [slug],
  );
  const row = result.rows[0];
  const closed =
    row &&
    (
      await client.query(
        "SELECT $1::timestamptz<=clock_timestamp() AS closed",
        [row.snapshot.closesAt],
      )
    ).rows[0].closed;
  if (!closed)
    throw new SelectionFailure(
      409,
      "Selection is available only after the call closes.",
    );
  const contract = row.snapshot;
  if (
    !["rehearsal", "production"].includes(contract.mode) ||
    !/^[A-Z]{3}$/.test(contract.currency) ||
    !Number.isSafeInteger(contract.selectedAmountMinor) ||
    contract.selectedAmountMinor <= 0 ||
    !Number.isSafeInteger(contract.runnerUpAmountMinor) ||
    contract.runnerUpAmountMinor <= 0
  )
    throw new SelectionFailure(
      409,
      "The frozen funding conditions are invalid. Selection is unavailable.",
    );
  if (
    (
      await client.query("SELECT 1 FROM call_selections WHERE call_slug=$1", [
        slug,
      ])
    ).rowCount
  )
    throw new SelectionFailure(
      409,
      "A selection has already been recorded. View the recorded selection before continuing.",
    );
  return {
    mode: contract.mode,
    hash: row.sha256 as string,
    selectedAmount: contract.selectedAmountMinor as number,
    runnerUpAmount: contract.runnerUpAmountMinor as number,
    currency: contract.currency as string,
  };
}

/** Lock and resolve the exact current revisions without loading contact fields. */
export async function recipients(client: PoolClient, slug: string, pair: Pair) {
  if (
    ![
      pair.selected.submissionId,
      pair.selected.revisionId,
      pair.runnerUp.submissionId,
      pair.runnerUp.revisionId,
    ].every(validId) ||
    pair.selected.submissionId === pair.runnerUp.submissionId
  )
    throw new SelectionFailure(400, "Choose two different submissions.");
  const result = await client.query(
    `SELECT s.id,r.id AS revision_id,r.author_name,r.filename,left(r.markdown,2048) AS title_source
     FROM submissions s JOIN submission_revisions r ON r.id=s.current_revision_id
     WHERE s.call_slug=$1 AND s.id=ANY($2::bigint[]) ORDER BY s.id FOR UPDATE OF s`,
    [slug, [pair.selected.submissionId, pair.runnerUp.submissionId]],
  );
  const resolve = (choice: Choice) => {
    const row = result.rows.find(
      (row) =>
        row.id === choice.submissionId && row.revision_id === choice.revisionId,
    );
    if (!row)
      throw new SelectionFailure(
        409,
        "A chosen revision is unavailable or has changed. Review your choices again.",
      );
    return {
      ...choice,
      author: row.author_name as string,
      title: specTitle(row.title_source, row.filename),
    };
  };
  return { selected: resolve(pair.selected), runnerUp: resolve(pair.runnerUp) };
}

/** Hold a live authenticated session through the write, including against logout. */
export async function lockSession(
  client: PoolClient,
  user: User,
  token: string,
) {
  const hash = digest(token);
  const result = await client.query(
    `SELECT s.token_hash FROM sessions s JOIN users u ON u.id=s.user_id
     WHERE s.token_hash=$1 AND s.user_id=$2 AND u.gitlab_user_id=$3 AND s.expires_at>clock_timestamp()
     FOR SHARE OF s`,
    [hash, user.id, user.gitlabId],
  );
  if (!result.rowCount) throw invalidConfirmation();
  return hash;
}
