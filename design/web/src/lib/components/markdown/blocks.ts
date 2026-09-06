import { Marked, type RendererObject, type Token, type Tokens } from "marked";

/** A parsed markdown table; cells hold inline markdown as HTML. */
export interface MarkdownTableData {
  headers: string[];
  rows: string[][];
  alignments: ("left" | "center" | "right")[];
}

/** One renderable block of a markdown document. */
export type MarkdownBlock =
  | { kind: "table"; table: MarkdownTableData }
  | { kind: "code"; code: string; language?: string }
  | { kind: "math"; latex: string }
  | { kind: "heading"; level: number; html: string }
  | { kind: "html"; html: string };

/* Display math arrives as `$$…$$` on its own lines. Markdown parsers treat it as
   a paragraph, so it is lifted out before parsing rather than after. */
const DISPLAY_MATH = /^\s*\$\$([\s\S]+?)\$\$\s*$/;

/** Typography classes per heading level, mirroring MarkdownRenderConfig.eigin. */
const headingClass = ["t-titleXl", "t-titleL", "t-titleM", "t-titleS", "t-titleS", "t-titleS"];

/**
 * Stamps generated typography classes onto the parser's output, so prose reads
 * from the same token scale as every other component instead of restating font
 * metrics in CSS.
 */
const renderer: RendererObject = {
  paragraph({ tokens }) {
    return `<p class="t-chatMessage">${this.parser.parseInline(tokens)}</p>\n`;
  },
  // The class sits on the list so items inherit it, which keeps loose and tight
  // lists working without reimplementing marked's item handling.
  list(token) {
    const tag = token.ordered ? "ol" : "ul";
    const start = token.ordered && token.start !== 1 ? ` start="${token.start}"` : "";
    const items = token.items.map((item) => this.listitem(item)).join("");
    return `<${tag}${start} class="t-chatMessage">${items}</${tag}>\n`;
  },
  blockquote({ tokens }) {
    return `<blockquote>${this.parser.parse(tokens)}</blockquote>\n`;
  },
  codespan({ text }) {
    return `<code class="t-code">${escapeHtml(text)}</code>`;
  },
};

const parser = new Marked({ renderer });

/**
 * Splits markdown into blocks, keeping code fences and display math as data so
 * they can render as components rather than raw HTML.
 */
export function toBlocks(markdown: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];

  for (const token of parser.lexer(markdown)) {
    const math = displayMath(token);
    if (math !== null) {
      blocks.push({ kind: "math", latex: math });
      continue;
    }

    if (token.type === "code") {
      const code = token as Tokens.Code;
      blocks.push({ kind: "code", code: code.text, language: code.lang || undefined });
      continue;
    }

    if (token.type === "table") {
      blocks.push({ kind: "table", table: tableData(token as Tokens.Table) });
      continue;
    }

    if (token.type === "heading") {
      const heading = token as Tokens.Heading;
      blocks.push({
        kind: "heading",
        level: heading.depth,
        html: parser.parseInline(heading.text) as string,
      });
      continue;
    }

    blocks.push({ kind: "html", html: parser.parser([token]) });
  }

  return blocks;
}

/** Pulls a table into plain data, with each cell's inline markdown rendered. */
function tableData(token: Tokens.Table): MarkdownTableData {
  return {
    headers: token.header.map((cell) => parser.parseInline(cell.text) as string),
    rows: token.rows.map((row) => row.map((cell) => parser.parseInline(cell.text) as string)),
    alignments: token.align.map((align) => align ?? "left"),
  };
}

/** The typography class for a heading level. */
export function headingTypography(level: number): string {
  return headingClass[Math.min(Math.max(level, 1), 6) - 1];
}

/** The LaTeX inside a display-math paragraph, or null for anything else. */
function displayMath(token: Token): string | null {
  if (token.type !== "paragraph" && token.type !== "text") return null;
  const match = DISPLAY_MATH.exec((token as Tokens.Paragraph).raw ?? "");
  return match ? match[1].trim() : null;
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
