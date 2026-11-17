import { locales } from "#lib/locales.ts";
import { loadNews } from "#lib/content/news/page.ts";
import type { EntryGenerator, PageLoad } from "./$types";

export const entries: EntryGenerator = () => locales.map((lang) => ({ lang }));
export const load: PageLoad = ({ params }) => loadNews(params.lang);
