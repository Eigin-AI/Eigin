<script lang="ts">
  let { isExpanded = false }: { isExpanded?: boolean } = $props();
</script>

<!--
  A plus that becomes a minus when expanded,
  signalling "reveal more here" rather than a chevron's navigation. Drawn in
  CSS because the icon set has no minus glyph (iOS uses SF Symbols).
-->
<span class="indicator" class:expanded={isExpanded} aria-hidden="true">
  <span class="bar horizontal"></span>
  <span class="bar vertical"></span>
</span>

<style>
  .indicator {
    position: relative;
    display: inline-block;
    /* Compact, so it reads as a trailing accent. */
    width: 16px;
    height: 16px;
    flex: none;
    color: var(--color-icon-standard-muted);
  }

  .bar {
    position: absolute;
    inset: 0;
    margin: auto;
    background: currentColor;
    border-radius: 1px;
  }

  .horizontal {
    width: 100%;
    height: 2px;
  }

  .vertical {
    width: 2px;
    height: 100%;
    transition:
      transform var(--motion-fast) var(--motion-easing-snap),
      opacity var(--motion-fast) var(--motion-easing-snap);
  }

  .indicator.expanded .vertical {
    transform: scaleY(0);
    opacity: 0;
  }
</style>
