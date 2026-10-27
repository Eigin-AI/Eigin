import { error } from "@sveltejs/kit";
import { trust } from "#lib/content/trust/index.ts";
import { site } from "#lib/content/site/index.ts";
import { locales, isLocale } from "#lib/locales.ts";
import type { PageLoad, EntryGenerator } from "./$types";

export const entries: EntryGenerator = () => locales.map((lang) => ({ lang }));
export const load: PageLoad = ({ params }) => {
  if (!isLocale(params.lang)) error(404, "Page not found");
  const locale = params.lang;
  return { locale, copy: trust[locale], site: site[locale] };
};
