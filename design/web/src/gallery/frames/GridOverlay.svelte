<script lang="ts">
  /**
   * The active breakpoint's grid, laid over whatever the frame is showing.
   *
   * Inverted from the usual column overlay: the space the grid *reserves* is
   * tinted — the outer margin, the inner margin, the gutters — and the columns
   * are left clear. Over a finished screen that reads far better than a wash
   * over the content you are trying to check, and it answers the question the
   * grid is actually for: does this edge sit where the margin says it should.
   */
  let { columns = 2 }: { columns?: number } = $props();

  /* One column, in terms the browser resolves against the frame's own width. */
  const track = $derived(
    `calc((100% - 2 * var(--grid-inner) - ${columns - 1} * var(--grid-gutter)) / ${columns})`,
  );

  const gutters = $derived(Array.from({ length: columns - 1 }, (_, index) => index + 1));
</script>

<div class="grid-overlay" aria-hidden="true">
  <!-- The outer margin: room a view may fill into. -->
  <span class="outer left"></span>
  <span class="outer right"></span>

  <!-- The inner margin: where content is meant to start. -->
  <span class="inner left"></span>
  <span class="inner right"></span>

  {#each gutters as index (index)}
    <span
      class="gutter"
      style:left="calc(var(--grid-inner) + {index} * ({track} + var(--grid-gutter)) - var(--grid-gutter))"
    ></span>
  {/each}
</div>

<style>
  .grid-overlay {
    position: absolute;
    inset: 0;
    z-index: 3;
    pointer-events: none;
  }

  /* The dashed line marks where content starts, so it sits on the margin's
     edge rather than a pixel past it. */
  .grid-overlay > * {
    position: absolute;
    top: 0;
    bottom: 0;
    box-sizing: border-box;
  }

  .left {
    left: 0;
  }

  .right {
    right: 0;
  }

  /* Two tones, so the two-part margin can be told apart at a glance. */
  .outer {
    width: var(--grid-outer);
    background: color-mix(in srgb, var(--color-icon-signal-negative) 24%, transparent);
  }

  .inner {
    width: var(--grid-inner);
    background: color-mix(in srgb, var(--color-icon-signal-negative) 10%, transparent);
    border-inline-end: 1px dashed
      color-mix(in srgb, var(--color-icon-signal-negative) 60%, transparent);
  }

  .inner.right {
    border-inline-end: none;
    border-inline-start: 1px dashed
      color-mix(in srgb, var(--color-icon-signal-negative) 60%, transparent);
  }

  .gutter {
    width: var(--grid-gutter);
    background: color-mix(in srgb, var(--color-icon-signal-negative) 14%, transparent);
  }
</style>
