import type { Locale } from "../../locales";
import type { TrustContent } from "./types";
import da from "./da";
import en from "./en";

export type { TrustContent } from "./types";
export const trust: Record<Locale, TrustContent> = { en, da };
