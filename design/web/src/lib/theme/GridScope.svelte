<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    children?: Snippet;
  }

  const { children }: Props = $props();
</script>

<!--
  Establishes a layout context: components inside measure breakpoints against
  this box rather than the viewport, which is what lets a screen inside a phone
  frame lay out like a phone. Nest one per frame.
-->
<div class="eigin-scope">
  <!-- Transparent to layout; a container query can't style its own container. -->
  <div class="eigin-grid">
    {@render children?.()}
  </div>
</div>

<style>
  .eigin-scope {
    container-type: inline-size;
    container-name: eigin;
  }

  /* The active grid breakpoint, resolved once so components can read
     --grid-inner/outer/gutter without knowing the width. iOS switches on the
     horizontal size class; these widths are the web equivalent.
     --chat-px-* are the chat-specific aliases of the same scale. */
  .eigin-grid {
    display: contents;
    --grid-columns: 2;
    --grid-outer: var(--grid-mobile-outer);
    --grid-inner: var(--grid-mobile-inner);
    --grid-gutter: var(--grid-mobile-gutter);
    --chat-px-large: var(--sizing-chat-px-large-mobile);
    --chat-px-small: var(--sizing-chat-px-small-mobile);
  }

  @container eigin (min-width: 768px) {
    .eigin-grid {
      --grid-columns: 4;
      --grid-outer: var(--grid-tablet-outer);
      --grid-inner: var(--grid-tablet-inner);
      --grid-gutter: var(--grid-tablet-gutter);
      --chat-px-large: var(--sizing-chat-px-large-tablet);
      --chat-px-small: var(--sizing-chat-px-small-tablet);
    }
  }

  @container eigin (min-width: 1280px) {
    .eigin-grid {
      --grid-columns: 4;
      --grid-outer: var(--grid-desktop-outer);
      --grid-inner: var(--grid-desktop-inner);
      --grid-gutter: var(--grid-desktop-gutter);
      --chat-px-large: var(--sizing-chat-px-large-desktop);
      --chat-px-small: var(--sizing-chat-px-small-desktop);
    }
  }
</style>
