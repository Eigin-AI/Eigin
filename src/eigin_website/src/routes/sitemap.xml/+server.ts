import { publishedPosts } from "#lib/content/news/published.ts";
import { renderSitemap } from "#lib/sitemap.ts";

export const prerender = true;
export const trailingSlash = "never";

/** Publish canonical page URLs for search-engine discovery. */
export function GET() {
  return new Response(renderSitemap(publishedPosts), {
    headers: { "Content-Type": "application/xml; charset=utf-8" },
  });
}
