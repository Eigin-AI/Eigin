import { callStatus } from "../call-status.ts";
import type { Pool } from "pg";
import type {
  PublicCall,
  PublicCallCard,
  PublicResult,
  PublicSpec,
} from "../publication.ts";

/** Anonymous reads project only explicitly public content and publication snapshots. */
export class PublishedCalls {
  private pool: Pool;
  private configured: PublicCall[];
  constructor(pool: Pool, configured: PublicCall[]) {
    this.pool = pool;
    this.configured = configured;
  }

  /** Resolve public call metadata with frozen dates and funding when available. */
  async call(slug: string) {
    const call = this.configured.find(
      (call) => call.publicListing && call.slug === slug,
    );
    if (!call) return null;
    const {
      rows: [row],
    } = await this.pool.query(
      `SELECT clock_timestamp() AS now,
      c.snapshot->>'opensAt' AS opens_at,c.snapshot->>'closesAt' AS closes_at,
      c.snapshot->>'selectedAmountMinor' AS selected_amount,c.snapshot->>'runnerUpAmountMinor' AS runner_amount,
      c.snapshot->>'currency' AS currency FROM (VALUES ($1::text)) requested(slug)
      LEFT JOIN call_contracts c ON c.slug=requested.slug`,
      [slug],
    );
    const effective = {
      ...call,
      opensAt: row.opens_at ?? call.opensAt,
      closesAt: row.closes_at ?? call.closesAt,
      selectedAmountMinor:
        row.selected_amount === null
          ? call.selectedAmountMinor
          : Number(row.selected_amount),
      runnerUpAmountMinor:
        row.runner_amount === null
          ? call.runnerUpAmountMinor
          : Number(row.runner_amount),
      currency: row.currency ?? call.currency,
    };
    return {
      ...effective,
      status: callStatus(
        effective.opensAt,
        effective.closesAt,
        row.now.getTime(),
      ),
    };
  }
  /** Public catalog entries currently accepting submissions. */
  async open() {
    const candidates = await Promise.all(
      this.configured
        .filter(({ publicListing }) => publicListing)
        .map(({ slug }) => this.call(slug)),
    );
    return candidates
      .filter((call) => call !== null)
      .filter((call) => call.status === "open")
      .sort(
        (a, b) =>
          Date.parse(a.closesAt) - Date.parse(b.closesAt) ||
          a.slug.localeCompare(b.slug),
      )
      .map((call) => {
        const { brief: _, ...summary } = call;
        return summary;
      });
  }
  /** Paginate closed public calls without loading any spec bodies or private review state. */
  async list(page = 1) {
    const current =
      Number.isSafeInteger(page) && page > 0 ? Math.min(page, 1000000) : 1;
    const configured = this.configured
      .filter((call) => call.publicListing)
      .map(({ slug, title, summary, closesAt }) => ({
        slug,
        title,
        summary,
        closesAt,
      }));
    const { rows } = await this.pool.query(
      `WITH configured AS (
      SELECT c.slug,c.title,c.summary,COALESCE(f.snapshot->>'closesAt',c."closesAt")::timestamptz AS closes_at
      FROM jsonb_to_recordset($1::jsonb) AS c(slug text,title text,summary text,"closesAt" text)
      LEFT JOIN call_contracts f ON f.slug=c.slug
    ), catalog AS (
      SELECT slug,title,summary,closes_at,NULL::timestamptz AS published_at,NULL::text AS selected_author,NULL::text AS runner_author FROM configured c
      WHERE closes_at<=clock_timestamp() AND NOT EXISTS (SELECT 1 FROM call_publications p WHERE p.call_slug=c.slug)
      UNION ALL
      SELECT call_slug,public_snapshot->>'title',public_snapshot->>'summary',
      (public_snapshot->>'closesAt')::timestamptz,published_at,public_snapshot->'selected'->>'author',public_snapshot->'runnerUp'->>'author' FROM call_publications
    ) SELECT slug,title,summary,closes_at,published_at,selected_author,runner_author FROM catalog
    ORDER BY closes_at DESC,slug LIMIT 21 OFFSET $2`,
      [JSON.stringify(configured), (current - 1) * 20],
    );
    const entries: PublicCallCard[] = rows.slice(0, 20).map((row) => ({
      slug: row.slug,
      title: row.title,
      summary: row.summary,
      closesAt: row.closes_at.toISOString(),
      publishedAt: row.published_at?.toISOString() ?? null,
      selectedAuthor: row.selected_author,
      runnerUpAuthor: row.runner_author,
    }));
    return { entries, page: current, hasNext: rows.length > 20 };
  }
  /** Results summaries exclude Markdown bodies and all publication audit fields. */
  async result(slug: string): Promise<PublicResult | null> {
    const {
      rows: [row],
    } = await this.pool.query(
      `SELECT jsonb_build_object(
      'slug',call_slug,'title',public_snapshot->'title','summary',public_snapshot->'summary',
      'closesAt',public_snapshot->'closesAt','currency',public_snapshot->'currency','copy',public_snapshot->'copy',
      'selected',jsonb_build_object('author',public_snapshot->'selected'->'author','title',public_snapshot->'selected'->'title','amountMinor',public_snapshot->'selected'->'amountMinor'),
      'runnerUp',jsonb_build_object('author',public_snapshot->'runnerUp'->'author','title',public_snapshot->'runnerUp'->'title','amountMinor',public_snapshot->'runnerUp'->'amountMinor')
      ) AS result,published_at FROM call_publications WHERE call_slug=$1`,
      [slug],
    );
    return row
      ? { ...row.result, publishedAt: row.published_at.toISOString() }
      : null;
  }
  /** Read one published spec by its public designation, never by private revision ID. */
  async spec(slug: string, place: string): Promise<PublicSpec | null> {
    if (place !== "selected" && place !== "runner-up") return null;
    const {
      rows: [row],
    } = await this.pool.query(
      `SELECT jsonb_build_object('author',spec->'author','title',spec->'title','markdown',spec->'markdown','amountMinor',spec->'amountMinor') AS spec
      FROM (SELECT public_snapshot->$2::text AS spec FROM call_publications WHERE call_slug=$1) chosen`,
      [slug, place === "selected" ? "selected" : "runnerUp"],
    );
    return row?.spec ?? null;
  }
}
