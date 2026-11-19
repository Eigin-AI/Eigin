import exampleSpec from "../../../../content/examples/schedule-follow-ups-from-a-conversation.md?raw";
import specGuide from "../../../../content/guides/spec.md?raw";
import processGuide from "../../../../content/guides/process.md?raw";
import { error, redirect } from "@sveltejs/kit";
const guides: Record<string, { title: string; body: string }> = {
  spec: {
    title: "What makes a good spec",
    body: specGuide,
  },
  example: {
    title: "Schedule follow-ups from a conversation",
    body:
      "[Download this example as Markdown](/guides/example/download)\n\n" +
      exampleSpec.replace(/^# .+\n\n/, ""),
  },
  process: {
    title: "Bring your best thinking",
    body: processGuide,
  },
};
export function entries() {
  return Object.keys(guides).map((slug) => ({ slug }));
}
export function load({ params }: { params: { slug: string } }) {
  if (params.slug === "terms") redirect(307, "/guides/participation-terms");
  const guide = guides[params.slug];
  if (!guide) error(404, "Guide not found");
  return guide;
}
