import type { Locale } from "../../locales";
import type { RoadmapContent } from "./types";
import en from "./en";
import da from "./da";

export const roadmap: Record<Locale, RoadmapContent> = { en, da };
export { roadmapData } from "./data";
