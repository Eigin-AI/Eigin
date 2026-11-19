import type { PoolClient } from "pg";
import type { PublicCall, PublicSnapshot, PublicSpec } from "../publication.ts";
import { specTitle } from "../spec-title.ts";
import { validateCopy } from "./selection-drafts.ts";
import { SelectionFailure } from "./selection-store.ts";

/** Resolve only recorded revisions under the same call lock used by selection writes. */
export async function publicationSnapshot(
  client: PoolClient,
  slug: string,
  call: PublicCall | null,
): Promise<PublicSnapshot> {
  if (!call?.publicListing || call.slug !== slug || !call.brief.trim())
    throw new SelectionFailure(409, "Public call content is unavailable.");
  const {
    rows: [contract],
  } = await client.query(
    `SELECT sha256,snapshot->>'closesAt' AS closes_at,snapshot->>'mode' AS mode,
    (snapshot->>'closesAt')::timestamptz<=clock_timestamp() AS closed
    FROM call_contracts WHERE slug=$1 FOR UPDATE`,
    [slug],
  );
  if (!contract?.closed || !["rehearsal", "production"].includes(contract.mode))
    throw new SelectionFailure(409, "Only a closed call can be published.");
  const {
    rows: [recorded],
  } = await client.query(
    `SELECT contract_sha256,selected_revision_id,runner_up_revision_id,selected_amount_minor,
    runner_up_amount_minor,currency,results_copy,mode FROM call_selections WHERE call_slug=$1 FOR UPDATE`,
    [slug],
  );
  if (
    !recorded ||
    recorded.mode !== contract.mode ||
    recorded.contract_sha256 !== contract.sha256
  )
    throw new SelectionFailure(
      409,
      "A complete recorded selection is required before publication.",
    );
  if (
    (
      await client.query("SELECT 1 FROM call_publications WHERE call_slug=$1", [
        slug,
      ])
    ).rowCount
  )
    throw new SelectionFailure(
      409,
      "These results have already been published.",
    );
  const copy = validateCopy(recorded.results_copy, true);
  const specs = await client.query(
    "SELECT id,author_name,filename,markdown FROM submission_revisions WHERE id=ANY($1::bigint[])",
    [[recorded.selected_revision_id, recorded.runner_up_revision_id]],
  );
  const resolve = (id: string, amount: string): PublicSpec => {
    const row = specs.rows.find((row) => row.id === id);
    if (!row)
      throw new SelectionFailure(409, "An awarded revision is unavailable.");
    return {
      author: row.author_name,
      title: specTitle(row.markdown, row.filename),
      markdown: row.markdown,
      amountMinor: Number(amount),
    };
  };
  return {
    slug,
    title: call.title,
    summary: call.summary,
    brief: call.brief,
    closesAt: contract.closes_at,
    currency: recorded.currency,
    copy,
    selected: resolve(
      recorded.selected_revision_id,
      recorded.selected_amount_minor,
    ),
    runnerUp: resolve(
      recorded.runner_up_revision_id,
      recorded.runner_up_amount_minor,
    ),
  };
}
