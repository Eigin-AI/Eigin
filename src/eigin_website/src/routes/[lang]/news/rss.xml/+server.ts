import { error } from "@sveltejs/kit";
import { locales, isLocale } from "#lib/locales.ts";
import { listPosts } from "#lib/content/news/index.ts";
import { renderFeed } from "#lib/content/news/feed.ts";
import type { RequestHandler, EntryGenerator } from "./$types";

export const prerender = true;
export const trailingSlash = "never";
export const entries: EntryGenerator = () => locales.map((lang) => ({ lang }));

/** Publish the localized news feed as a static XML resource. */
export const GET: RequestHandler = ({ params }) => {
  if (!isLocale(params.lang)) error(404, "Page not found");
  return new Response(renderFeed(params.lang, listPosts(params.lang)), {
    headers: {
      "Content-Type": "application/rss+xml; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
    },
  });
};
