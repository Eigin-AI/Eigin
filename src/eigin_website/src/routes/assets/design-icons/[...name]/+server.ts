import { designArtwork } from "../../../../lib/present/artwork";
import { error } from "@sveltejs/kit";

export const prerender = true;
export const entries = () =>
  Object.keys(designArtwork).map((path) => ({ name: path.slice("/assets/design-icons/".length) }));

/** Publish the generated design-system artwork for decks and the authoring catalogue. */
export function GET({ params }: { params: { name: string } }) {
  const svg = designArtwork[`/assets/design-icons/${params.name}`];
  if (!svg) error(404, "Unknown design-system icon");
  return new Response(svg, {
    headers: { "Content-Type": "image/svg+xml", "X-Content-Type-Options": "nosniff" },
  });
}
