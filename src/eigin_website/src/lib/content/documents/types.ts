/** Published document copy and its locale translations. */
export interface DocumentContent {
  title: string;
  description: string;
  updated?: string;
  introduction: ((
    { html: string; action?: never } | { action: { label: string; href: string }; html?: never }
  ) & { label?: string })[];
  sections: { id: string; title: string; html: string }[];
}
