import { escapeXml } from "#lib/xml.ts";
import social from "#lib/content/social.json";
import type { Locale } from "#lib/locales.ts";
import type { NewsPost } from "./catalog";
import { newsCopy } from "./copy";

/** Serialize localized article summaries as an RSS 2.0 feed. */
export function renderFeed(locale: Locale, posts: NewsPost[]): string {
  const copy = newsCopy[locale];
  const base = `${social.origin}/${locale}/news/`;
  const items = posts
    .map((post) => {
      const url = escapeXml(`${base}${post.slug}/`);
      return `<item><title>${escapeXml(post.title)}</title><description>${escapeXml(post.description)}</description><link>${url}</link><guid isPermaLink="true">${url}</guid><pubDate>${new Date(`${post.date}T00:00:00Z`).toUTCString()}</pubDate></item>`;
    })
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
<title>${copy.heading} · Eigin</title><link>${base}</link><description>${escapeXml(copy.description)}</description><language>${locale}</language>
<atom:link href="${base}rss.xml" rel="self" type="application/rss+xml" />
${items}
</channel></rss>`;
}
