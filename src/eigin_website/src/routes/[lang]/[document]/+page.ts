import { error } from "@sveltejs/kit";
import { documentSlugs, documentContent, isDocumentSlug } from "#lib/content/documents/index.ts";
import { site } from "#lib/content/site/index.ts";
import { locales, isLocale } from "#lib/locales.ts";
import type { PageLoad, EntryGenerator } from "./$types";

export const entries: EntryGenerator = () =>
  locales.flatMap((lang) => documentSlugs.map((document) => ({ lang, document })));

export const load: PageLoad = ({ params }) => {
  if (!isLocale(params.lang) || !isDocumentSlug(params.document)) error(404, "Page not found");
  return {
    locale: params.lang,
    slug: params.document,
    content: documentContent(params.document, params.lang),
    site: site[params.lang],
  };
};
