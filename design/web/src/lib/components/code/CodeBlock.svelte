<script lang="ts">
  /* highlight.js escapes its input before wrapping tokens in spans, so its
     output is safe to inject. Whitespace inside <pre> is significant, which
     rules out a per-line disable comment. */
  /* eslint-disable svelte/no-at-html-tags */
  import hljs from "highlight.js/lib/common";
  import "./highlight.css";

  interface Props {
    code: string;
    /** Fence language. Omitted means no highlighting: hljs guesses poorly. */
    language?: string;
    /**
     * While streaming, code renders unhighlighted: highlighting re-tokenises the
     * whole block, too expensive to repeat per chunk.
     */
    streaming?: boolean;
  }

  const { code, language, streaming = false }: Props = $props();

  const highlighted = $derived.by(() => {
    if (streaming || !language || !code) return null;
    if (!hljs.getLanguage(language)) return null;
    return hljs.highlight(code, { language, ignoreIllegals: true }).value;
  });
</script>

<div class="code-block">
  <pre class="t-code"><code class="hljs"
      >{#if highlighted}{@html highlighted}{:else}{code}{/if}</code
    ></pre>
</div>

<style>
  .code-block {
    /* Long lines scroll rather than wrap, as the iOS card does. */
    overflow-x: auto;
    background: var(--color-surface-standard-elevated);
    border-radius: var(--radius-card);
  }

  pre {
    margin: 0;
    /* Horizontal gains the code font's optical inset so equal padding reads even
       against the vertical, the way iOS's EiginCodeBlock pads. */
    padding-block: var(--spacing-n16);
    padding-inline: calc(var(--spacing-n16) + var(--text-optical-inset-code, 0px));
    width: max-content;
    min-width: 100%;
    box-sizing: border-box;
    color: var(--color-code-plain);
  }

  code {
    font: inherit;
  }
</style>
