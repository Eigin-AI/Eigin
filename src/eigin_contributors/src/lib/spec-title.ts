import { marked } from "marked";

/** Use a bounded top-level Markdown title, falling back to the uploaded filename. */
export function specTitle(markdown: string, filename: string): string {
  const heading = marked
    .lexer(markdown.slice(0, 2048))
    .find((token) => token.type === "heading" && token.depth === 1);
  return (heading?.type === "heading" ? heading.text : filename).slice(0, 160);
}
