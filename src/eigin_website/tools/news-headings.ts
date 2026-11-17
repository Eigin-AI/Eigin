type MarkdownNode = {
  type: string;
  depth?: number;
  data?: { hProperties?: Record<string, unknown> };
  children?: MarkdownNode[];
};

/** Apply shared typography classes to Markdown section headings. */
export function newsHeadings() {
  return (tree: MarkdownNode) => {
    const visit = (node: MarkdownNode) => {
      if (node.type === "heading" && node.depth) {
        const typography =
          node.depth === 2 ? "t-titleM" : node.depth === 3 ? "t-titleS" : "t-titleXS";
        node.data ??= {};
        node.data.hProperties ??= {};
        node.data.hProperties.className = [typography];
      }
      node.children?.forEach(visit);
    };
    visit(tree);
  };
}
