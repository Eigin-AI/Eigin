import social from "#lib/content/social.json" with { type: "json" };
import { locales } from "#lib/locales.ts";
import { unlocalizedSections } from "#lib/unlocalized.ts";
import { escapeXml } from "#lib/xml.ts";
import type { NewsPost } from "#lib/content/news/catalog.ts";

/** List canonical, localized public pages and published news in sitemap XML. */
export function renderSitemap(posts: NewsPost[]): string {
  const paths = new Set([
    ...locales.flatMap((locale) => [
      `/${locale}/`,
      ...unlocalizedSections.map((section) => `/${locale}/${section}/`),
    ]),
    ...posts.map((post) => `/${post.locale}/news/${post.slug}/`),
  ]);
  const urls = [...paths]
    .sort()
    .map((path) => `<url><loc>${escapeXml(`${social.origin}${path}`)}</loc></url>`);
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.join("\n")}
</urlset>`;
}
