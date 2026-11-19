import { dev } from "$app/env";
import { error } from "@sveltejs/kit";
import body from "../../../../content/guides/participation-terms.md?raw";

export function load() {
  if (!dev) error(404, "Not found");
  const [introduction, ...sections] = body
    .replace(/^# Participation terms\s*/, "")
    .split(/^## /m);
  return {
    introduction,
    sections: sections.map((section) => {
      const [title, ...lines] = section.split("\n");
      return {
        id: title
          .replace(/^\d+\.\s*/, "")
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/-$/, ""),
        title,
        body: lines.join("\n").trim(),
      };
    }),
  };
}
