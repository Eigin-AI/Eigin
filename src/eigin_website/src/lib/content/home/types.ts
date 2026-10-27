import type { IconName } from "@eigin/ui";

/** A short chat that plays back beside a feature bullet. */
export type ChatExample = {
  label: string;
  ask: string;
  /** A short, human-readable description of the illustrative background work. */
  tools: string[];
  reply: string;
  /** Answers the reply offers to go on with. */
  options?: { label: string; description: string; symbol: IconName }[];
  /** An action that waits for your approval. */
  permission?: { headline: string; value: string; symbol: IconName };
};

/** The chat chrome's labels, matching the app's. */
export type ChatLabels = {
  agent: string;
  placeholder: string;
  allow: string;
  play: string;
  pause: string;
  examples: string;
};

export type FeatureContent = {
  id: "personal" | "teams";
  label: string;
  /** Shown beside the label while the feature isn't available yet. */
  status?: string;
  title: string;
  body: string;
  placeholder: string;
} & (
  | { examples: [ChatExample, ...ChatExample[]]; chat: ChatLabels; bullets?: never }
  | { bullets: string[]; examples?: never; chat?: never }
);

export type HomeContent = {
  title: string;
  description: string;
  hero: { headline: string; body: string; placeholder: string };
  mission: { title: string; paragraphs: string[] };
  personal: FeatureContent;
  privacy: {
    title: string;
    body: string;
    action: { label: string; href: string };
    promises: { title: string; body: string; illustration: IconName }[];
  };
  team: FeatureContent;
  pricing: {
    title: string;
    body: string;
    action: string;
    plans: { name: string; price: string; detail: string; status?: string }[];
  };
  open: { title: string; body: string; links: { label: string; detail: string; href: string }[] };
  faq: {
    title: string;
    /** Answers are trusted HTML, so they can hold links. */
    items: { question: string; answer: string }[];
    more: string;
    support: { label: string; href: string };
  };
  get: {
    motion: { pause: string; play: string };
    title: string;
    visual: string;
    badge: string;
    more: string;
    roadmap: { label: string; href: string };
  };
};
