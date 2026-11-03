import { iconAssets } from "@eigin/ui";

/** Canonical slide URLs use the same generated SVG registry as the website Icon component. */
export const designArtwork = Object.fromEntries(
  Object.entries(iconAssets).map(([name, svg]) => [`/assets/design-icons/${name}.svg`, svg]),
);

const legacy = import.meta.glob("../../../static/assets/{icons,images}/**/*.svg", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

/** Legacy deck paths remain available alongside the generated design-system assets. */
export const artwork = {
  ...Object.fromEntries(
    Object.entries(legacy).map(([path, svg]) => [path.slice(path.indexOf("/assets/")), svg]),
  ),
  ...designArtwork,
};
