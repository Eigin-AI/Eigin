<script lang="ts">
  import type { MarkdownTableData } from "./blocks";

  interface Props {
    table: MarkdownTableData;
  }

  const { table }: Props = $props();

  const columns = $derived(table.alignments.length);
  const lastRow = $derived(table.rows.length - 1);
</script>

<!--
  A rounded card matching the code block, with a faint grid inside: a stronger
  rule under the header, lighter ones between rows and columns. Wide tables
  scroll within the card; columns cap so long cells wrap.
-->
<div class="table-card">
  <div class="scroll">
    <div class="grid" style:--columns={columns}>
      {#if table.headers.length}
        {#each table.headers as header, column (column)}
          <div
            class="cell header t-miniLabel"
            class:first-column={column === 0}
            class:last-column={column === columns - 1}
            style:text-align={table.alignments[column]}
          >
            <!-- eslint-disable-next-line svelte/no-at-html-tags — inline markdown -->
            {@html header}
          </div>
        {/each}
      {/if}

      {#each table.rows as row, index (index)}
        {#each row as cell, column (column)}
          <div
            class="cell t-chatMessage"
            class:first-column={column === 0}
            class:last-column={column === columns - 1}
            class:last-row={index === lastRow}
            style:text-align={table.alignments[column]}
          >
            <!-- eslint-disable-next-line svelte/no-at-html-tags — inline markdown -->
            {@html cell}
          </div>
        {/each}
      {/each}
    </div>
  </div>
</div>

<style>
  .table-card {
    background: var(--color-surface-standard-elevated);
    border-radius: var(--radius-card);
    container-type: inline-size;
  }

  .scroll {
    overflow-x: auto;
  }

  .grid {
    display: grid;
    /* Each column may claim an equal share of the visible width, never less
       than the floor: past that a long cell wraps rather than stretching the
       table. The cap belongs on the track, since a grid item stretches to fill
       whatever track it is given. */
    grid-template-columns: repeat(
      var(--columns),
      fit-content(max(240px, calc(100cqw / var(--columns))))
    );
    min-width: 100%;
    width: max-content;
  }

  .cell {
    /* Interior columns share a gutter around the rule; outer ones clear the
       card edge. The gutter is the spacing token plus the prose font's optical
       inset, so the text edge lines up with the card's vertical padding as it
       does on iOS. Cells keep the prose's untrimmed line boxes. */
    text-box: normal;
    padding: var(--spacing-n8) var(--spacing-n12);
    color: var(--color-text-standard-base);
    border-right: 1px solid color-mix(in srgb, var(--color-border-standard-base) 35%, transparent);
    border-bottom: 1px solid color-mix(in srgb, var(--color-border-standard-base) 35%, transparent);
  }

  .header {
    color: var(--color-text-standard-muted);
    padding-top: var(--spacing-n16);
    /* The header's rule stays the strongest line in the grid. */
    border-bottom-color: color-mix(in srgb, var(--color-border-standard-base) 65%, transparent);
  }

  .first-column {
    padding-left: calc(var(--spacing-n16) + var(--text-optical-inset-chatMessage, 0px));
  }

  .last-column {
    padding-right: calc(var(--spacing-n16) + var(--text-optical-inset-chatMessage, 0px));
    border-right: none;
  }

  .last-row {
    padding-bottom: var(--spacing-n16);
    border-bottom: none;
  }
</style>
