import type { Locale } from "../../locales";
import type { HomeContent } from "./types";
import en from "./en";
import da from "./da";

export type { HomeContent } from "./types";
export const home: Record<Locale, HomeContent> = { en, da };
