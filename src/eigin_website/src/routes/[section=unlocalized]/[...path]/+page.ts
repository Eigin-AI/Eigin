import { error } from "@sveltejs/kit";
import { unlocalizedSections, isUnlocalizedSection } from "#lib/unlocalized.ts";
import { listPosts, findPost } from "#lib/content/news/index.ts";
import type { EntryGenerator, PageLoad } from "./$types";

export const entries: EntryGenerator = () => [
  ...unlocalizedSections.map((section) => ({ section, path: "" })),
  ...listPosts("en").map(({ slug }) => ({ section: "news" as const, path: slug })),
];

export const load: PageLoad = ({ params }) => {
  if (!isUnlocalizedSection(params.section)) error(404, "Page not found");
  const path = params.path.replace(/\/$/, "");
  if (path && (params.section !== "news" || !findPost("en", path))) {
    error(404, "Page not found");
  }
  return { path: `${params.section}/${path ? `${path}/` : ""}` };
};
