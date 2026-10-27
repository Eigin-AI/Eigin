import type { Locale } from "../../locales";
import type { SiteContent } from "./types";
import en from "./en";
import da from "./da";

export type { SiteContent } from "./types";
export const site: Record<Locale, SiteContent> = { en, da };
