import { createCatalog } from "./catalog";

const metadata = import.meta.glob("./posts/*/*.svx", {
  eager: true,
  query: "?news-metadata",
  import: "default",
});

/** Published article metadata for navigation, feeds, and search discovery. */
export const publishedPosts = createCatalog(metadata);
