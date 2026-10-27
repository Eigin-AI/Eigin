import privacy from "./privacy/en";
import terms from "./terms/en";
import contact from "./contact/en";
import support from "./support/en";
import contactDa from "./contact/da";
import supportDa from "./support/da";
import type { DocumentContent } from "./types";
import type { Locale } from "#lib/locales.ts";

export const documentSlugs = ["privacy", "terms", "contact", "support"] as const;
export type DocumentSlug = (typeof documentSlugs)[number];
const documents = { privacy, terms, contact, support };

/** Select translated contact/support copy; legal documents remain in English. */
export function documentContent(slug: DocumentSlug, locale: Locale): DocumentContent {
  if (locale === "da" && slug === "contact") return contactDa;
  if (locale === "da" && slug === "support") return supportDa;
  return documents[slug];
}

/** Whether a route names one of the published documents. */
export function isDocumentSlug(value: string): value is DocumentSlug {
  return documentSlugs.some((slug) => slug === value);
}

/** Localize document links while preserving the published wording. */
export function documentHtml(html: string, locale: Locale): string {
  return html.replace(/href="\/(privacy|terms|contact|support)\/"/g, `href="/${locale}/$1/"`);
}
