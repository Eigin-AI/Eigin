import type { Locale } from "../../locales";

export type RoadmapItemCopy = { title: string; description?: string };

/** An editable roadmap entry; English is required and Danish is optional. */
export type RoadmapItem = {
  id: string;
  copy: { en: RoadmapItemCopy } & Partial<Record<Exclude<Locale, "en">, RoadmapItemCopy>>;
  version?: { label: string; href?: string };
};

/** A release group in display order, newest first. */
export type RoadmapRelease = {
  id: string;
  period?: Record<Locale, string>;
  items: RoadmapItem[];
};

/** The roadmap's editable source of truth, independent of page markup. */
export type RoadmapData = {
  active: RoadmapItem[];
  planned: RoadmapItem[];
  launched: RoadmapRelease[];
};

export type RoadmapContent = {
  title: string;
  description: string;
  heading: string;
  introduction: string;
  sourceLabel: string;
  communityLabel: string;
  empty: string;
  active: { title: string };
  planned: { title: string };
  launched: { title: string };
};
