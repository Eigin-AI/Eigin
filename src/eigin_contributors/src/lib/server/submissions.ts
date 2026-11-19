import { createHash } from "node:crypto";
import type { Pool } from "pg";
import type { User } from "./auth.ts";

export const digest = (text: string) =>
  createHash("sha256").update(text).digest("hex");
export type Agreement = { version: string; body: string; sha256: string };
export type Contract = {
  slug: string;
  opensAt: string;
  closesAt: string;
  selectedAmountMinor: number;
  runnerUpAmountMinor: number;
  currency: string;
  mode: "rehearsal";
  cla: Agreement;
  terms: Agreement;
};
export const consentStatements = {
  cla: "I agree to the Eigin Individual CLA v1.0.",
  terms: "I accept the participation terms.",
};

export type Revision = {
  id: string;
  markdown: string;
  filename: string;
  sha256: string;
  receivedAt: string;
  email: string;
  author: string;
  authorEmail: string;
  acceptance: {
    cla: { version: string; sha256: string; statement: string };
    terms: { version: string; sha256: string; statement: string };
    mode: string;
  };
};
export class SubmissionFailure extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}
const revision = (row: Record<string, any>): Revision => ({
  id: row.id,
  markdown: row.markdown,
  filename: row.filename,
  sha256: row.sha256,
  receivedAt: new Date(row.received_at).toISOString(),
  email: row.contact_email,
  author: row.author_name,
  authorEmail: row.author_email,
  acceptance: {
    cla: {
      version: row.cla_version,
      sha256: row.cla_sha256,
      statement: row.consent.cla,
    },
    terms: {
      version: row.terms_version,
      sha256: row.terms_sha256,
      statement: row.consent.terms,
    },
    mode: row.consent.mode,
  },
});

/** Own submissions only. No caller-selected owner or revision is exposed through HTTP. */
export async function current(
  pool: Pool,
  userId: string,
  slug: string,
): Promise<Revision | null> {
  const result = await pool.query(
    "SELECT r.*, c.version AS cla_version, t.version AS terms_version FROM submissions s JOIN submission_revisions r ON r.id = s.current_revision_id JOIN agreement_snapshots c ON c.sha256=r.cla_sha256 JOIN agreement_snapshots t ON t.sha256=r.terms_sha256 WHERE s.user_id = $1 AND s.call_slug = $2",
    [userId, slug],
  );
  return result.rows[0] ? revision(result.rows[0]) : null;
}

/** Prefill only acceptance of the exact current agreement and statement. */
export function acceptedAgreements(saved: Revision | null, contract: Contract) {
  const evidence = saved?.acceptance;
  const sameMode = evidence?.mode === contract.mode;
  const matches = (kind: "cla" | "terms") =>
    !!(
      sameMode &&
      evidence &&
      evidence[kind].version === contract[kind].version &&
      evidence[kind].sha256 === contract[kind].sha256 &&
      evidence[kind].statement === consentStatements[kind]
    );
  return {
    cla: matches("cla"),
    terms: matches("terms"),
  };
}

/** Validate a bounded upload, then atomically replace the current private revision. */
export async function submit(
  pool: Pool,
  user: User,
  contract: Contract,
  form: FormData,
): Promise<Revision> {
  const text = (name: string, max: number) => {
    const raw = form.get(name);
    if (
      typeof raw !== "string" ||
      !raw.trim() ||
      raw.length > max ||
      /[\x00-\x1f\x7f]/.test(raw)
    )
      throw new SubmissionFailure(`Check ${name}.`);
    return raw.trim();
  };
  const email = text("email", 254);
  const author = text("author", 200);
  const authorEmail = text("authorEmail", 254);
  if (![email, authorEmail].every((v) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)))
    throw new SubmissionFailure(
      "Enter valid contact and author email addresses.",
    );
  if (!["acceptedCla", "acceptedTerms"].every((k) => form.get(k) === "on"))
    throw new SubmissionFailure("Accept the CLA and participation terms.");
  if (
    form.get("claVersion") !== contract.cla.version ||
    form.get("termsVersion") !== contract.terms.version ||
    form.get("claHash") !== contract.cla.sha256 ||
    form.get("termsHash") !== contract.terms.sha256
  )
    throw new SubmissionFailure(
      "The agreements changed. Reload and review the terms.",
      409,
    );
  const expected = form.get("expectedRevision") || null;
  if (
    expected !== null &&
    (typeof expected !== "string" || !/^\d+$/.test(expected))
  )
    throw new SubmissionFailure("Invalid revision.");
  const file = form.get("file");
  let upload: { markdown: string; filename: string } | null = null;
  if (file instanceof File && file.name) {
    if (
      !file.name.toLowerCase().endsWith(".md") ||
      file.name.length > 255 ||
      file.size > 256 * 1024
    )
      throw new SubmissionFailure(
        "Choose a Markdown (.md) file no larger than 256 KiB.",
      );
    let markdown: string;
    try {
      markdown = new TextDecoder("utf-8", { fatal: true }).decode(
        await file.arrayBuffer(),
      );
    } catch {
      throw new SubmissionFailure("Choose a valid UTF-8 Markdown file.");
    }
    if (!markdown.trim() || markdown.includes("\0"))
      throw new SubmissionFailure(
        "Choose a nonempty Markdown file without null characters.",
      );
    upload = {
      markdown,
      filename: file.name.replace(/[\\/\x00-\x1f\x7f]/g, "_"),
    };
  }
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const snapshot = JSON.stringify(contract);
    const hash = digest(snapshot);
    await client.query(
      "INSERT INTO call_contracts VALUES ($1,$2,$3) ON CONFLICT DO NOTHING",
      [contract.slug, hash, snapshot],
    );
    const locked = await client.query(
      "SELECT sha256 FROM call_contracts WHERE slug=$1 FOR UPDATE",
      [contract.slug],
    );
    if (locked.rows[0].sha256 !== hash)
      throw new SubmissionFailure(
        "Call conditions have changed. Contact the administrator before submitting.",
        409,
      );
    await client.query(
      "INSERT INTO submissions (call_slug,user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING",
      [contract.slug, user.id],
    );
    const entry = (
      await client.query(
        "SELECT * FROM submissions WHERE call_slug=$1 AND user_id=$2 FOR UPDATE",
        [contract.slug, user.id],
      )
    ).rows[0];
    if (entry.current_revision_id !== expected)
      throw new SubmissionFailure(
        "A newer revision exists. Reload before replacing it.",
        409,
      );
    const limit = 20;
    const {
      rows: [history],
    } = await client.query(
      "SELECT count(*)::int AS used FROM (SELECT 1 FROM submission_revisions WHERE submission_id=$1 LIMIT $2) recent",
      [entry.id, limit],
    );
    if (history.used >= limit)
      throw new SubmissionFailure(
        `This call allows ${limit} saved versions. Your latest version is unchanged.`,
        409,
      );
    const content =
      upload ??
      (entry.current_revision_id
        ? (
            await client.query(
              "SELECT markdown,filename FROM submission_revisions WHERE id=$1",
              [entry.current_revision_id],
            )
          ).rows[0]
        : null);
    if (!content) throw new SubmissionFailure("Choose a Markdown file.");
    for (const agreement of [contract.cla, contract.terms]) {
      if (digest(agreement.body) !== agreement.sha256)
        throw new Error("Agreement snapshot mismatch");
      await client.query(
        "INSERT INTO agreement_snapshots VALUES ($1,$2,$3) ON CONFLICT DO NOTHING",
        [agreement.sha256, agreement.version, agreement.body],
      );
    }
    const received = (await client.query("SELECT clock_timestamp() AS now"))
      .rows[0].now;
    if (
      received < new Date(contract.opensAt) ||
      received >= new Date(contract.closesAt)
    )
      throw new SubmissionFailure(
        "Submissions are closed. Your previous revision is unchanged.",
        409,
      );
    const consent = {
      mode: contract.mode,
      gitlabId: user.gitlabId,
      username: user.username,
      ...consentStatements,
      claVersion: contract.cla.version,
      termsVersion: contract.terms.version,
      acceptedAt: received.toISOString(),
    };
    const result = await client.query(
      "INSERT INTO submission_revisions (submission_id,markdown,filename,sha256,received_at,contact_email,author_name,author_email,cla_sha256,terms_sha256,consent) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING *",
      [
        entry.id,
        content.markdown,
        content.filename,
        digest(content.markdown),
        received,
        email,
        author,
        authorEmail,
        contract.cla.sha256,
        contract.terms.sha256,
        consent,
      ],
    );
    await client.query(
      "UPDATE submissions SET current_revision_id=$1 WHERE id=$2",
      [result.rows[0].id, entry.id],
    );
    await client.query("COMMIT");
    return revision({
      ...result.rows[0],
      cla_version: contract.cla.version,
      terms_version: contract.terms.version,
    });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
