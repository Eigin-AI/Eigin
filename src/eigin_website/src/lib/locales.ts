export const locales = ["en", "da"] as const;
export type Locale = (typeof locales)[number];
export const languageNames: Record<Locale, string> = { en: "English", da: "Dansk" };

/** Resolve homepage fragments from any localized page. */
export function siteHref(href: string, locale: Locale): string {
  return href.startsWith("#") ? `/${locale}/${href}` : href;
}

/** Whether a route segment is a supported locale. */
export function isLocale(value: string | undefined): value is Locale {
  return locales.some((locale) => locale === value);
}

/** Select the first supported browser language, with English as fallback. */
export function preferredLocale(languages: readonly string[]): Locale {
  for (const language of languages) {
    const base = language.toLowerCase().split("-")[0];
    if (isLocale(base)) return base;
  }
  return "en";
}
