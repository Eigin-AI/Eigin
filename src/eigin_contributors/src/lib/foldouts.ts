import { marked } from "marked";

export type FoldoutPart =
  | { kind: "copy"; body: string }
  | {
      kind: "foldouts";
      introduction: string;
      items: { title: string; body: string }[];
    };
/** Explicit Markdown fences select disclosures; the first heading sets the item depth. */
export function foldoutParts(text: string): FoldoutPart[] {
  const tokens = marked.lexer(text);
  const result: FoldoutPart[] = [];
  let copy = "";
  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index];
    if (token.type !== "html" || token.raw.trim() !== "<!-- foldouts -->") {
      copy += token.raw;
      continue;
    }
    const end = tokens.findIndex(
      (item, i) =>
        i > index &&
        item.type === "html" &&
        item.raw.trim() === "<!-- end-foldouts -->",
    );
    if (end < 0) {
      copy += token.raw;
      continue;
    }
    if (copy.trim()) result.push({ kind: "copy", body: copy });
    copy = "";
    const items: { title: string; body: string }[] = [];
    let introduction = "";
    let depth: number | undefined;
    for (const item of tokens.slice(index + 1, end)) {
      if (
        item.type === "heading" &&
        (depth === undefined || item.depth === depth)
      ) {
        depth ??= item.depth;
        items.push({ title: item.text, body: "" });
      } else if (items.length) items[items.length - 1].body += item.raw;
      else introduction += item.raw;
    }
    result.push({ kind: "foldouts", introduction, items });
    index = end;
  }
  if (copy.trim()) result.push({ kind: "copy", body: copy });
  return result;
}
