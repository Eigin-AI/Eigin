import { locales, type Locale } from "#lib/locales.ts";

/** Metadata for a published, localized news article. */
export type NewsPost = {
  slug: string;
  locale: Locale;
  title: string;
  description: string;
  date: string;
};

/** Validate discovered content and return a deterministic newest-first catalogue. */
export function createCatalog(entries: Record<string, unknown>): NewsPost[] {
  const posts = Object.entries(entries).map(([path, metadata]) => {
    const fail = (reason: string): never => {
      throw new Error(`News ${path}: ${reason}`);
    };
    const match = path.match(/\/([a-z0-9]+(?:-[a-z0-9]+)*)\/(en|da)\.svx$/);
    if (!match) return fail("expected <url-safe-slug>/<en|da>.svx");
    if (!metadata || typeof metadata !== "object") return fail("missing frontmatter");
    const fields = metadata as Record<string, unknown>;
    for (const key of ["title", "description", "date"]) {
      if (typeof fields[key] !== "string" || !fields[key].trim()) return fail(`missing ${key}`);
    }
    const { title, description, date } = fields as Record<string, string>;
    const parsed = new Date(`${date}T00:00:00Z`);
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
      !Number.isFinite(parsed.getTime()) ||
      parsed.toISOString().slice(0, 10) !== date
    ) {
      return fail("date must be a quoted, valid YYYY-MM-DD");
    }
    return { slug: match[1], locale: match[2] as Locale, title, description, date };
  });
  const seen = new Set<string>();
  for (const post of posts) {
    const key = `${post.slug}/${post.locale}`;
    if (seen.has(key)) throw new Error(`News ${key}.svx: duplicate article`);
    seen.add(key);
  }
  for (const post of posts) {
    for (const locale of locales) {
      if (!seen.has(`${post.slug}/${locale}`))
        throw new Error(`News ${post.slug}/${locale}.svx: missing translation`);
    }
  }
  return posts.sort((a, b) => b.date.localeCompare(a.date) || a.slug.localeCompare(b.slug));
}
