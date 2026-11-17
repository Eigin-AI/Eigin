import { locales } from "#lib/locales.ts";
import { listPosts } from "#lib/content/news/index.ts";
import { loadNews } from "#lib/content/news/page.ts";
import type { EntryGenerator, PageLoad } from "./$types";

export const entries: EntryGenerator = () =>
  locales.flatMap((lang) => listPosts(lang).map(({ slug }) => ({ lang, slug })));
export const load: PageLoad = ({ params }) => loadNews(params.lang, params.slug);
