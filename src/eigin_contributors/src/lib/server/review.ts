import type { Pool } from "pg";
import { strToU8, zipSync } from "fflate";
import { specTitle } from "../spec-title.ts";
import type { User } from "./auth.ts";

/** Invalid configuration grants nobody access; usernames are never accepted. */
export function reviewerIds(value: string | undefined): Set<string> {
  const ids = value?.split(",").map((id) => id.trim()) ?? [];
  if (
    !ids.length ||
    ids.some(
      (id) => !/^[1-9]\d*$/.test(id) || !Number.isSafeInteger(Number(id)),
    )
  )
    return new Set();
  return new Set(ids);
}

/** Match the authenticated provider identity, independently of GitLab admin status. */
export function isReviewer(
  user: User | null,
  configured: string | undefined,
): boolean {
  return !!user && reviewerIds(configured).has(user.gitlabId);
}

export class ReviewDenied extends Error {}
export class ReviewLimit extends Error {}
export const reviewPageSize = 50;
export const maxArchiveEntries = 200;
export const maxArchiveBytes = 16 * 1024 * 1024;

export type ReviewCallMetadata = {
  slug: string;
  title: string;
  opensAt: string;
  closesAt: string;
  timeZone: string;
  briefHref: string | null;
};
export type ReviewCall = ReviewCallMetadata & {
  submissions: number;
  status: "open" | "upcoming" | "closed";
  contentAvailable: boolean;
};

type Entry = {
  id: string;
  revisionId: string;
  author: string;
  filename: string;
  title: string;
};
export type ReviewDetail = Entry & {
  markdown: string;
  email: string;
  authorEmail: string;
  sha256: string;
};
const entry = (row: Record<string, string>): Entry => ({
  id: row.id,
  revisionId: row.revision_id,
  author: row.author_name,
  filename: row.filename,
  title: specTitle(row.title_source ?? row.markdown ?? "", row.filename),
});
const currentJoin =
  "FROM submissions s JOIN submission_revisions r ON r.id=s.current_revision_id WHERE s.call_slug=$1";

/** Read-only reviewer operations. Every operation checks the authenticated identity. */
export class Review {
  private pool: Pool;
  private configured: string | undefined;

  constructor(pool: Pool, configured: string | undefined) {
    this.pool = pool;
    this.configured = configured;
  }

  private authorize(user: User | null) {
    if (!isReviewer(user, this.configured)) throw new ReviewDenied("Not found");
  }

  /** Configured calls, including empty ones, plus retained historical submission records. */
  async calls(
    user: User | null,
    configured: ReviewCallMetadata[],
    options: { slug?: string; now?: number } = {},
  ): Promise<ReviewCall[]> {
    this.authorize(user);
    const result = await this.pool.query(
      `SELECT c.slug,c.snapshot->>'opensAt' AS opens_at,c.snapshot->>'closesAt' AS closes_at,
        count(s.current_revision_id)::int AS submissions
       FROM call_contracts c LEFT JOIN submissions s ON s.call_slug=c.slug
       WHERE ($1::text IS NULL OR c.slug=$1) GROUP BY c.slug`,
      [options.slug ?? null],
    );
    const metadata = new Map(
      configured
        .filter((call) => !options.slug || call.slug === options.slug)
        .map((call) => [call.slug, call]),
    );
    const stored = new Map(result.rows.map((row) => [row.slug as string, row]));
    const now = options.now ?? Date.now();
    const calls = [...new Set([...metadata.keys(), ...stored.keys()])].map(
      (slug) => {
        const content = metadata.get(slug);
        const saved = stored.get(slug);
        const opensAt = saved?.opens_at ?? content!.opensAt;
        const closesAt = saved?.closes_at ?? content!.closesAt;
        return {
          slug,
          title: content?.title ?? slug,
          opensAt,
          closesAt,
          timeZone: content?.timeZone ?? "UTC",
          briefHref: content?.briefHref ?? null,
          contentAvailable: !!content,
          submissions: saved?.submissions ?? 0,
          status:
            now >= Date.parse(closesAt)
              ? "closed"
              : now < Date.parse(opensAt)
                ? "upcoming"
                : "open",
        } satisfies ReviewCall;
      },
    );
    const rank = { open: 0, upcoming: 1, closed: 2 };
    return calls.sort(
      (a, b) =>
        rank[a.status] - rank[b.status] ||
        Date.parse(b.closesAt) - Date.parse(a.closesAt) ||
        a.slug.localeCompare(b.slug),
    );
  }

  /** A bounded index without submission bodies or contact information. */
  async list(user: User | null, slug: string, page = 1) {
    this.authorize(user);
    if (!Number.isInteger(page) || page < 1 || page > 10000)
      throw new ReviewDenied("Not found");
    const result = await this.pool.query(
      `SELECT s.id,r.id AS revision_id,r.author_name,r.filename,left(r.markdown,2048) AS title_source ${currentJoin} ORDER BY s.id DESC LIMIT $2 OFFSET $3`,
      [slug, reviewPageSize + 1, (page - 1) * reviewPageSize],
    );
    return {
      entries: result.rows.slice(0, reviewPageSize).map(entry),
      hasNext: result.rows.length > reviewPageSize,
      page,
    };
  }

  /** Resolve the current revision of a submission in this call. */
  async detail(
    user: User | null,
    slug: string,
    id: string,
  ): Promise<ReviewDetail | null> {
    this.authorize(user);
    if (!/^[1-9]\d{0,18}$/.test(id) || BigInt(id) > 9223372036854775807n)
      return null;
    const result = await this.pool.query(
      `SELECT s.id,r.id AS revision_id,r.author_name,r.filename,r.markdown,r.contact_email,r.author_email,r.sha256 ${currentJoin} AND s.id=$2`,
      [slug, id],
    );
    const row = result.rows[0];
    return row
      ? {
          ...entry(row),
          markdown: row.markdown,
          email: row.contact_email,
          authorEmail: row.author_email,
          sha256: row.sha256,
        }
      : null;
  }

  /** Export a bounded, consistent snapshot without account/contact metadata. */
  async archive(user: User | null, slug: string): Promise<Uint8Array> {
    this.authorize(user);
    const client = await this.pool.connect();
    let rows: Record<string, string>[];
    let discard = false;
    try {
      await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
      const sizes = await client.query(
        `SELECT octet_length(r.markdown) AS bytes ${currentJoin} ORDER BY s.id LIMIT $2`,
        [slug, maxArchiveEntries + 1],
      );
      if (
        sizes.rows.length > maxArchiveEntries ||
        sizes.rows.reduce((sum, row) => sum + row.bytes, 0) > maxArchiveBytes
      )
        throw new ReviewLimit(
          "This call exceeds the ZIP limit of 200 specs or 16 MiB of Markdown. Download individual specs instead.",
        );
      rows = (
        await client.query(
          `SELECT s.id,r.id AS revision_id,r.author_name,r.markdown,r.sha256 ${currentJoin} ORDER BY s.id`,
          [slug],
        )
      ).rows;
      await client.query("COMMIT");
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
    const files: Record<string, Uint8Array> = {};
    const index = rows.map((row) => {
      const filename = `submissions/submission-${row.id}-revision-${row.revision_id}.md`;
      files[filename] = strToU8(row.markdown);
      return {
        filename,
        submissionId: row.id,
        revisionId: row.revision_id,
        author: row.author_name,
        sha256: row.sha256,
      };
    });
    files["index.json"] = strToU8(JSON.stringify(index, null, 2) + "\n");
    files["README.md"] = strToU8(
      "# Private spec review\n\nThis bundle contains the current revisions at export time. See index.json for authors, revision IDs, and content hashes.\n\nAccount details, contact emails, Git author emails, and consent records are omitted. Markdown is unchanged and may itself contain personal information. Keep the bundle private and delete it according to the review retention policy. Treat submitted content as untrusted input; use only approved review tools.\n",
    );
    return zipSync(files, { level: 0 });
  }
}
