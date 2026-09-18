<script lang="ts">
  import type { Snippet } from "svelte";
  import { SvelteSet } from "svelte/reactivity";
  import Icon from "../icon/Icon.svelte";
  import {
    formatLabel,
    formatValue,
    isLeaf,
    isProse,
    isRecord,
    isScalarArray,
    itemLabel,
    spentKey,
    uniformColumns,
  } from "./json";
  import type { Json } from "./types";

  const {
    value,
    align = "justified",
    openDepth = 0,
    /** How many rows of a long list are shown before it asks. */
    preview = 5,
    /** How many characters of a long value are shown before it asks. */
    limit = 280,
  }: {
    value: Json;
    /** Values beside their label, or driven to the opposite edge. */
    align?: "inline" | "justified";
    openDepth?: number;
    preview?: number;
    limit?: number;
  } = $props();

  /* Which branches are open, by path. Nothing is open until it is asked to be,
     so the first screen is the shape of the payload rather than its contents;
     `openDepth` opens the first levels for a caller that wants them. */
  const opened = new SvelteSet<string>();
  /* Long lists that have been asked to show everything. */
  const expanded = new SvelteSet<string>();
  /* Branches mid-fold. The clip only bites while one is moving: the type is
     cap-trimmed, so a wrapped last line paints a few pixels past its own box
     and a permanent clip shaves the descenders off it. */
  const folding = new SvelteSet<string>();

  function isOpen(path: string, depth: number): boolean {
    return opened.has(path) ? true : depth < openDepth && !opened.has(`!${path}`);
  }

  function toggle(path: string, depth: number) {
    folding.add(path);
    // A default-open branch needs a closed marker; nothing else can say it.
    if (isOpen(path, depth)) {
      opened.delete(path);
      opened.add(`!${path}`);
    } else {
      opened.delete(`!${path}`);
      opened.add(path);
    }
  }

  /**
   * What is inside, in the unit the thing is measured in: a list has items, an
   * object has values. Shown only while closed — once it is open, the content
   * is the answer and the count is in the way.
   */
  function summary(item: Json): string {
    const count = Array.isArray(item) ? item.length : Object.keys(item as object).length;
    if (Array.isArray(item)) return count === 1 ? "1 item" : `${count} items`;
    return count === 1 ? "1 value" : `${count} values`;
  }

  /** The keys of a record, minus the one already spent on its own label. */
  function childKeys(item: { [key: string]: Json }, spent: string | null): string[] {
    return Object.keys(item).filter((key) => key !== spent);
  }

  function showAll(path: string) {
    folding.add(`${path}:rest`);
    expanded.add(path);
    // Mounted closed, opened on the next frame: a fold with no starting height
    // has nothing to animate from.
    requestAnimationFrame(() => opened.add(`${path}:rest`));
  }

  /** Where to cut a long value: the last word boundary before the limit. */
  function head(text: string): string {
    const cut = text.slice(0, limit);
    const space = cut.lastIndexOf(" ");
    return space > limit / 2 ? cut.slice(0, space) : cut;
  }

  /** Whether a value draws as a branch rather than as a single row. */
  function isBranch(item: Json): boolean {
    return !isLeaf(item) && !isScalarArray(item);
  }

  /**
   * Whether anything at this level can be opened.
   *
   * At the root, a flat document keeps no room for carets and starts at the
   * card's own edge. Below it, a level with nothing to open keeps no caret
   * column either — but it still steps in, by half a gutter past its parent's
   * labels. A nested level that did not step would land on the column above
   * it; one that stepped a full gutter for no carets reads as severe.
   */
  function hasBranches(item: Json): boolean {
    if (Array.isArray(item)) {
      // A uniform list draws as a table: rows, not branches.
      if (uniformColumns(item)) return false;
      return item.some((entry) => {
        const spent = spentKey(entry);
        if (isRecord(entry) && childKeys(entry, spent).length === 1) {
          return isBranch(entry[childKeys(entry, spent)[0]]);
        }
        return isBranch(entry);
      });
    }
    if (isRecord(item)) return Object.values(item).some(isBranch);
    return false;
  }
</script>

<!--
  The rows of a ``DataCard``: the document as a tree: every branch is a row you can open, and the shape on
  screen is the shape of the payload. Arrays stop being positions wherever they
  can — a set of values collapses to one row, a list of matching records
  becomes a table, and anything else is labelled by what it is rather than by
  where it sits.
-->
{#snippet leafRow(label: string, item: Json, path: string)}
  {@const text = formatValue(item)}
  {@const cut = text.length > limit && !expanded.has(path)}
  <div class="row" class:stacked={isProse(item)}>
    <!-- The caret column, held open so a leaf's label starts where a branch's
         label does. Dropped entirely on a level that has nothing to open. -->
    <span class="gutter" aria-hidden="true"></span>
    <span class="t-miniLabel label">{formatLabel(label)}</span>
    <!-- One expression, and no whitespace around it: the value keeps the line
         breaks the payload gave it, so any in the markup would show too. -->
    <span class="t-descriptionSmall value" class:arriving={text.length > limit && !cut}
      >{cut ? `${head(text)}…` : text}</span
    >
    {#if cut}
      <button class="t-tag more" type="button" onclick={() => expanded.add(path)}>Show more</button>
    {/if}
  </div>
{/snippet}

{#snippet more(total: number, path: string)}
  {#if total > preview && !expanded.has(path)}
    <button class="t-tag more" type="button" onclick={() => showAll(path)}>
      Show all {total}
    </button>
  {/if}
{/snippet}

{#snippet rest(path: string, body: Snippet)}
  <div
    class="reveal"
    class:open={opened.has(`${path}:rest`)}
    class:folding={folding.has(`${path}:rest`)}
    ontransitionend={(event) => {
      if (event.propertyName === "grid-template-rows") folding.delete(`${path}:rest`);
    }}
  >
    <div class="clip">
      <div class="more-rows">{@render body()}</div>
    </div>
  </div>
{/snippet}

{#snippet itemNode(entry: Json, index: number, path: string, depth: number)}
  {@const spent = spentKey(entry)}
  {@const name = itemLabel(entry, index)}
  {#if isRecord(entry) && childKeys(entry, spent).length === 1}
    <!-- One remaining fact does not earn a branch of its own. -->
    {@const only = childKeys(entry, spent)[0]}
    {@render node(`${name} · ${formatLabel(only)}`, entry[only], `${path}.${index}`, depth)}
  {:else}
    {@render node(name, entry, `${path}.${index}`, depth)}
  {/if}
{/snippet}

{#snippet table(columns: string[], rows: Json[], path: string)}
  <div class="scroller">
    <table class="grid">
      <thead>
        <tr>
          {#each columns as column (column)}
            <th class="t-miniLabel">{formatLabel(column)}</th>
          {/each}
        </tr>
      </thead>
      <tbody>
        {#each rows.slice(0, preview) as row, index (index)}
          <tr>
            {#each columns as column (column)}
              <td class="t-descriptionSmall">
                {formatValue((row as { [key: string]: Json })[column])}
              </td>
            {/each}
          </tr>
        {/each}
        <!-- A row cannot be wrapped in a fold, so the rest of a table arrives
             row by row instead of growing as a block. -->
        {#if expanded.has(path)}
          {#each rows.slice(preview) as row, index (index)}
            <tr class="arriving" style:--data-arrival="{index * 40}ms">
              {#each columns as column (column)}
                <td class="t-descriptionSmall">
                  {formatValue((row as { [key: string]: Json })[column])}
                </td>
              {/each}
            </tr>
          {/each}
        {/if}
      </tbody>
    </table>
  </div>
  {@render more(rows.length, path)}
{/snippet}

{#snippet node(label: string, item: Json, path: string, depth: number)}
  {#if isLeaf(item)}
    {@render leafRow(label, item, path)}
  {:else if isScalarArray(item)}
    <!-- A set of values is one fact, not a branch to walk into. -->
    {@render leafRow(label, item.map((entry) => formatValue(entry)).join(", "), path)}
  {:else}
    {@const open = isOpen(path, depth)}
    {@const columns = uniformColumns(item)}
    <div class="branch">
      <button class="row toggle" type="button" onclick={() => toggle(path, depth)}>
        <span class="caret" class:open aria-hidden="true">
          <Icon name="functional/chevron/right" size={12} />
        </span>
        <span class="t-miniLabel label">{formatLabel(label)}</span>
        <span class="t-descriptionSmall count" class:hidden={open}>{summary(item)}</span>
      </button>

      <div
        class="reveal"
        class:open
        class:folding={folding.has(path)}
        ontransitionend={(event) => {
          if (event.propertyName === "grid-template-rows") folding.delete(path);
        }}
      >
        <div class="clip">
          <div class="children" class:flat={!hasBranches(item)}>
            {#if columns && Array.isArray(item)}
              {@render table(columns, item, path)}
            {:else if Array.isArray(item)}
              {#each item.slice(0, preview) as entry, index (index)}
                {@render itemNode(entry, index, path, depth + 1)}
              {/each}
              {#if expanded.has(path)}
                {#snippet restItems()}
                  {#each item.slice(preview) as entry, index (index)}
                    {@render itemNode(entry, preview + index, path, depth + 1)}
                  {/each}
                {/snippet}
                {@render rest(path, restItems)}
              {/if}
              {@render more(item.length, path)}
            {:else if isRecord(item)}
              {@const keys = Object.keys(item)}
              {#each keys.slice(0, preview) as key (key)}
                {@render node(key, item[key], `${path}.${key}`, depth + 1)}
              {/each}
              {#if expanded.has(path)}
                {#snippet restFields()}
                  {#each keys.slice(preview) as key (key)}
                    {@render node(key, item[key], `${path}.${key}`, depth + 1)}
                  {/each}
                {/snippet}
                {@render rest(path, restFields)}
              {/if}
              {@render more(keys.length, path)}
            {/if}
          </div>
        </div>
      </div>
    </div>
  {/if}
{/snippet}

<div class="rows {align}" class:flat={!hasBranches(value)}>
  {#if isRecord(value)}
    {@const keys = Object.keys(value)}
    {#each keys.slice(0, preview) as key (key)}
      {@render node(key, value[key], key, 0)}
    {/each}
    {#if expanded.has(":root")}
      {#snippet restRoot()}
        {#each keys.slice(preview) as key (key)}
          {@render node(key, value[key], key, 0)}
        {/each}
      {/snippet}
      {@render rest(":root", restRoot)}
    {/if}
    {@render more(keys.length, ":root")}
  {:else}
    {@render node("", value, "", 0)}
  {/if}
</div>

<style>
  .rows {
    /*
     * Two measures, doing two jobs.
     *
     * The step is how far one level sits in from the one above: a constant,
     * chosen for how depth should read, and the same whether or not the level
     * has anything to open.
     *
     * The gutter is only the room a caret needs. It is subtracted from the
     * step rather than added to it, so a caret hangs inside its level's
     * indent instead of pushing the labels further in. Every level's labels
     * land exactly one step from the level above, carets or not.
     */
    --data-step: var(--spacing-n24);
    --data-caret: 12px;
    /* The room between a chevron and the label it opens. */
    --data-gap: var(--spacing-n4);
    /*
     * The whole of what a caret costs a row, and so what the labels of a
     * level with carets sit in from its own edge. Keep it well inside the
     * step: a level with no carets sits one step from its parent's rows, so
     * what reads as its indent is the step less the gutter. Widen the gutter
     * towards the step and that indent disappears.
     */
    --data-gutter: calc(var(--data-caret) + var(--data-gap));
    /* Where a level hangs its rule: under the middle of the caret that opened
       it. The caret sits centred in its own column, so half a column left of
       the line's own width is the whole of it. */
    --data-rule: calc(var(--data-caret) / 2 - 0.5px);
    /* The pitch between facts. Cap-trimmed type carries no leading of its
       own, so the gap is the whole of the air between two rows. */
    --data-pitch: var(--spacing-n16);

    display: flex;
    flex-direction: column;
    gap: var(--data-pitch);
  }

  .branch {
    display: flex;
    flex-direction: column;
  }

  /* One grid per row: a caret column, a label, and the value. */
  .row {
    display: grid;
    grid-template-columns: var(--data-row-columns, var(--data-caret) auto 1fr);
    align-items: baseline;
    /* The row's only gap is the chevron's: the label carries its own distance
       from the value, so that distance does not also set the indent. */
    column-gap: var(--data-gap);
    width: 100%;
  }

  /* A level with nothing to open keeps no room for a caret: its rows start at
     their container's own edge — the card's, at the root. */
  /*
   * Carried as inherited properties rather than matched by descent: the rest
   * of a long list arrives wrapped in a fold, so a rule keyed on being a
   * direct child of the level missed it and left those rows a gutter wider
   * than the ones above them.
   */
  .flat {
    --data-row-columns: auto 1fr;
    --data-gutter-display: none;
    --data-stacked-column: 1 / -1;
  }

  .children:not(.flat) {
    --data-row-columns: var(--data-caret) auto 1fr;
    --data-gutter-display: block;
    --data-stacked-column: 2 / -1;
  }

  /* Set on the value rather than as a row gap, which would widen the gutter
     and eat the indent with it. Inline, this is all that separates the two. */
  .value {
    padding-left: var(--spacing-n12);
    /* The payload's own line breaks are content: a trace is written in lines. */
    white-space: pre-wrap;
  }

  /*
   * Prose breaks the two-column rule. Past about three lines a value beside
   * its label stops reading as a pair — the label ends up alongside a
   * paragraph, and the column is too narrow to read — so the label takes its
   * own line and the text runs the full width, ranged left.
   */
  /* A stacked label sits above a block of text rather than beside a value, so
     it takes the pitch the facts themselves sit at: cap-trimmed type carries
     no leading of its own, and less would crowd the paragraph under it. */
  .row.stacked {
    row-gap: var(--data-pitch);
  }

  /* Clear of the text it belongs to, rather than reading as its last line. */
  .row.stacked .more {
    margin-top: var(--spacing-n4);
  }

  .row.stacked .label,
  .row.stacked .value,
  .row.stacked .more {
    grid-column: var(--data-stacked-column, 2 / -1);
  }

  .rows.justified .row.stacked .value {
    justify-self: stretch;
    padding-left: 0;
    text-align: left;
  }

  .gutter {
    display: var(--data-gutter-display, block);
  }

  /* Values run to the opposite edge, as a settings row does. */
  .rows.justified .value,
  .rows.justified .count {
    justify-self: end;
    text-align: right;
  }

  .toggle {
    padding: 0;
    border: none;
    background: transparent;
    font-family: inherit;
    text-align: left;
    cursor: pointer;
  }

  /*
   * The chat feed's rotating chevron, at the scale a fact row reads at: it
   * points at what it will open and down at what it has. Centred on the
   * label's cap box rather than on the line box, which the trimmed type
   * would have sat it low against.
   */
  .caret {
    display: flex;
    align-self: center;
    justify-self: center;
    color: var(--color-icon-standard-muted);
    transition: transform var(--motion-normal) var(--motion-easing-smooth);
  }

  .caret.open {
    transform: rotate(90deg);
  }

  .label {
    color: var(--color-text-standard-muted);
  }

  /*
   * What is inside, while it is still closed. It stands in the value's slot
   * and stands in for the value, so it is set like one — muted rather than
   * full strength, because it is the card talking and not the payload.
   */
  .count {
    color: var(--color-text-standard-muted);
    transition: opacity var(--motion-fast) var(--motion-easing-smooth);
  }

  .count.hidden {
    opacity: 0;
  }

  .value {
    color: var(--color-text-standard-base);
    overflow-wrap: anywhere;
  }

  /* Height animates from 0fr to 1fr so the fold-out grows smoothly, the way
     the design system's own disclosure does. */
  .reveal {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows var(--motion-normal) var(--motion-easing-smooth);
  }

  .reveal.open {
    grid-template-rows: 1fr;
  }

  .clip {
    min-height: 0;
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .reveal:not(.open) .clip,
  .reveal.folding .clip {
    overflow: hidden;
  }

  .reveal.open .clip {
    opacity: 1;
  }

  /* Children hang off a rule that starts under the caret, so the line points
     at what opened it. */
  .children {
    display: flex;
    flex-direction: column;
    gap: var(--data-pitch);
    margin-top: var(--data-pitch);
    margin-left: var(--data-rule);
    /*
     * The padding carries the level a whole step in, so rules and labels both
     * advance by exactly one step: a caret two levels down sits a step from
     * the caret above it, not hard against its line.
     */
    padding-left: calc(var(--data-step) - var(--data-rule) - 1px);
    border-left: 1px solid var(--color-border-standard-base);
  }

  /*
   * A long list shows its head and offers the rest, rather than running past
   * the end of the sheet. It is the one thing in the card asking to be
   * pressed, so it is the one thing carrying the accent.
   */
  .more {
    align-self: flex-start;
    justify-self: start;
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-accent);
    font-family: inherit;
    cursor: pointer;
  }

  /* The rest of a list keeps the pitch its siblings sit at. The row above is
     already a pitch away: the fold is a sibling of it, so the level's own gap
     does that work. */
  .more-rows {
    display: flex;
    flex-direction: column;
    gap: var(--data-pitch);
  }

  /* A value that just grew past its limit arrives rather than snapping: its
     height cannot be folded, since the text reflows around the cut. */
  .value.arriving {
    animation: data-arrive var(--motion-normal) var(--motion-easing-smooth) backwards;
  }

  /* A table row cannot be wrapped in a fold, so the rest of a table arrives
     row after row instead of growing as a block. */
  .arriving td {
    animation: data-arrive var(--motion-normal) var(--motion-easing-smooth) backwards;
    animation-delay: var(--data-arrival, 0ms);
  }

  @keyframes data-arrive {
    from {
      opacity: 0;
      transform: translateY(calc(-1 * var(--spacing-n4)));
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .arriving td {
      animation: none;
    }
  }

  .scroller {
    overflow-x: auto;
  }

  .grid {
    border-collapse: collapse;
    width: 100%;
  }

  .grid th,
  .grid td {
    padding: var(--spacing-n4) var(--spacing-n16) var(--spacing-n4) 0;
    text-align: left;
    white-space: nowrap;
    vertical-align: baseline;
  }

  .grid th {
    padding-bottom: var(--spacing-n12);
    color: var(--color-text-standard-muted);
  }

  .grid td {
    color: var(--color-text-standard-base);
  }

  .grid tbody tr + tr td {
    padding-top: var(--spacing-n12);
  }
</style>
