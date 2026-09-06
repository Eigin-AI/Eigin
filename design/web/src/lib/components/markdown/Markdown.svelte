<script lang="ts">
  import katex from "katex";
  import "katex/dist/katex.min.css";
  import CodeBlock from "../code/CodeBlock.svelte";
  import MarkdownTable from "./MarkdownTable.svelte";
  import { headingTypography, toBlocks } from "./blocks";
  import "./markdown.css";

  interface Props {
    text: string;
    /** Streaming blocks render code unhighlighted. */
    streaming?: boolean;
  }

  const { text, streaming = false }: Props = $props();

  const blocks = $derived(toBlocks(text));

  function math(latex: string): string {
    try {
      return katex.renderToString(latex, { displayMode: true, throwOnError: false });
    } catch {
      return latex;
    }
  }
</script>

<div class="markdown">
  {#each blocks as block, i (i)}
    {#if block.kind === "code"}
      <CodeBlock code={block.code} language={block.language} {streaming} />
    {:else if block.kind === "table"}
      <MarkdownTable table={block.table} />
    {:else if block.kind === "math"}
      <div class="math">
        <!-- eslint-disable-next-line svelte/no-at-html-tags — KaTeX output -->
        {@html math(block.latex)}
      </div>
    {:else if block.kind === "heading"}
      <!-- H1 and H2 uppercase to match the brand's display headings. CSS does it,
           so the underlying text stays intact for selection and search. -->
      <svelte:element
        this={`h${block.level}`}
        class="heading level-{block.level} {headingTypography(block.level)}"
      >
        <!-- eslint-disable-next-line svelte/no-at-html-tags — inline markdown -->
        {@html block.html}
      </svelte:element>
    {:else}
      <!-- eslint-disable-next-line svelte/no-at-html-tags — parsed markdown -->
      {@html block.html}
    {/if}
  {/each}
</div>

<style>
  .markdown {
    display: flex;
    flex-direction: column;
    /* MarkdownRenderConfig.blockSpacing */
    gap: var(--spacing-n16);
  }

  .math {
    overflow-x: auto;
    color: var(--color-text-standard-base);
  }

  .heading {
    margin: 0;
    color: var(--color-text-standard-base);
  }

  .level-1,
  .level-2 {
    text-transform: uppercase;
  }
</style>
