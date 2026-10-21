<script lang="ts">
  import type { Snippet } from "svelte";
  import SoftEdge, { type SoftEdgeShape } from "./SoftEdge.svelte";
  import { scrollEdges, type ScrollEdges } from "./scrollEdges";

  interface Props {
    /** Floats over the top of the scroll, usually a transparent header. */
    header?: Snippet;
    /** Floats over the bottom of the scroll, usually the composer. */
    footer?: Snippet;
    /** Keeps the footer's own spacing instead of adding the composer gap. */
    flushFooter?: boolean;
    /** The scroll container, for scrolling it from outside. */
    scroller?: HTMLElement;
    /** Where the soft edges sit around the header and footer. */
    shape?: SoftEdgeShape;
    /** Softens only the top edge, as a sheet does. */
    topOnly?: boolean;
    children: Snippet;
  }

  let {
    header,
    footer,
    flushFooter = false,
    scroller = $bindable(),
    shape = "screen",
    topOnly = false,
    children,
  }: Props = $props();

  let headerHeight = $state(0);
  let footerHeight = $state(0);
  let edges = $state<ScrollEdges>({ top: false, bottom: false, gutter: 0 });

  /* The space below a composer footer, as the footer pads it. */
  const FOOTER_INSET =
    "max(var(--spacing-n16), var(--eigin-safe-area-bottom, env(safe-area-inset-bottom)))";
</script>

<!--
  A scroll region whose edges soften the content: dimmed and blurred as it
  nears a screen edge, only while there is more beyond it. The header and
  footer float over the scroll with no surface of their own, and the scroll
  reserves their height. Fills the room its parent gives it.
-->
<div class="region">
  <div
    class="scroll"
    bind:this={scroller}
    use:scrollEdges={(next) => (edges = next)}
    style:padding-top="{headerHeight}px"
    style:padding-bottom={footer
      ? `calc(${footerHeight}px + ${flushFooter ? "0px" : "var(--spacing-n16)"})`
      : undefined}
  >
    {@render children()}
  </div>

  <SoftEdge
    edge="top"
    control={headerHeight}
    inset={shape === "screen" ? "var(--eigin-safe-area-top, 0px)" : "0px"}
    active={edges.top}
    gutter={edges.gutter}
    {shape}
  />
  {#if !topOnly}
    <SoftEdge
      edge="bottom"
      control={footerHeight}
      inset={flushFooter ? "0px" : FOOTER_INSET}
      active={edges.bottom}
      gutter={edges.gutter}
      {shape}
    />
  {/if}

  {#if header}
    <div class="header" bind:clientHeight={headerHeight}>
      {@render header()}
    </div>
  {/if}
  {#if footer}
    <div class="footer" class:flush={flushFooter} bind:clientHeight={footerHeight}>
      {@render footer()}
    </div>
  {/if}
</div>

<style>
  /* Isolated, so the controls' z-index stays inside the region and a sheet
     or overlay on the screen still covers them. Clipped, so a soft edge's
     blur, which runs past the screen edge, never makes the screen scroll. */
  .region {
    position: relative;
    isolation: isolate;
    overflow: clip;
    display: flex;
    flex: 1 1 auto;
    flex-direction: column;
    min-height: 0;
  }

  /* Its own stacking context, so nothing in the content, however high its
     z-index, rises above the soft edges. */
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    isolation: isolate;
  }

  /* Above the soft edges, so the controls stay sharp. */
  .header,
  .footer {
    position: absolute;
    right: 0;
    left: 0;
    z-index: 1;
  }

  .header {
    top: 0;
  }

  .footer {
    bottom: 0;
    padding-bottom: max(
      var(--spacing-n16),
      var(--eigin-safe-area-bottom, env(safe-area-inset-bottom))
    );
  }

  .footer.flush {
    padding-bottom: 0;
  }
</style>
