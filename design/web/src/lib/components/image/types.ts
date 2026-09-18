/**
 * What an image in a conversation is showing.
 *
 * In order: `blocked` or `loading`, then `loaded` or `failed`. `blocked` is a
 * remote image not fetched yet — fetching tells a host the model chose that you
 * are here.
 */
export type ImageState = "loading" | "loaded" | "failed" | "blocked";
