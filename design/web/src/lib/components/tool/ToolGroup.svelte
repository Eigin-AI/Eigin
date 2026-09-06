<script lang="ts">
  import Icon from "../icon/Icon.svelte";
  import ToolRow from "./ToolRow.svelte";
  import type { ToolCall } from "./types";

  interface Props {
    tools: ToolCall[];
    /** Opening a tool's detail; the sheet itself lives in the app. */
    onselect?: (tool: ToolCall) => void;
  }

  const { tools, onselect }: Props = $props();

  const grouped = $derived(tools.length > 1);
  const last = $derived(tools[tools.length - 1]);
  let expanded = $state(false);

  function toggle() {
    if (grouped) expanded = !expanded;
    else if (tools[0]) onselect?.(tools[0]);
  }
</script>

<div class="tool-group">
  <button
    class="summary"
    type="button"
    onclick={toggle}
    aria-expanded={grouped ? expanded : undefined}
  >
    {#if grouped}
      <span class="chevron" class:open={expanded}>
        <Icon name="functional/chevron/down" size="fill" />
      </span>
    {/if}

    {#if expanded}
      <span class="count-label t-chatMessage">{tools.length} tools used</span>
    {:else if last}
      <ToolRow tool={last} />
      {#if grouped}
        <span class="count t-chatMessage">({tools.length})</span>
      {/if}
    {/if}
  </button>

  <!-- Grid-row height animation: the only way to transition to auto height. -->
  <div class="panel" class:open={expanded}>
    <div class="rows">
      {#each tools as tool (tool.id)}
        <button class="row" type="button" onclick={() => onselect?.(tool)}>
          <ToolRow {tool} />
        </button>
      {/each}
    </div>
  </div>
</div>

<style>
  /* The feed pads its tool-group case with breakpoint.inner, the same
     inset brand messages carry. */
  .tool-group {
    box-sizing: border-box;
    width: 100%;
    padding: 0 var(--chat-px-large);
    display: flex;
    flex-direction: column;
    align-items: flex-start;
  }

  .summary,
  .row {
    display: flex;
    align-items: center;
    padding: 0;
    border: none;
    background: none;
    color: inherit;
    font: inherit;
    text-align: left;
    cursor: pointer;
  }

  /* One asset for both states: pointing right when closed, down when open. */
  .chevron {
    display: flex;
    flex: none;
    width: 10px;
    height: 10px;
    margin-right: var(--spacing-n8);
    color: var(--color-text-standard-muted);
    opacity: 0.4;
    transform: rotate(-90deg);
    transition: transform var(--motion-normal) var(--motion-easing-smooth);
  }

  .chevron.open {
    transform: rotate(0deg);
  }

  /* Matches a tool row's box exactly, so swapping the summary for the count
     label keeps the header's height and the group only grows downwards. */
  .count-label,
  .count {
    color: var(--color-text-standard-muted);
    opacity: 0.4;
    padding: var(--spacing-n4) 0;
    margin-block: calc(var(--spacing-n12) / 2);
  }

  .count {
    padding-left: var(--spacing-n4);
  }

  .panel {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows var(--motion-slow) var(--motion-easing-gentle);
  }

  .panel.open {
    grid-template-rows: 1fr;
  }

  /* Expanded rows line up with the collapsed summary's text, not the caret.
     The horizontal padding pair keeps descenders alive despite the clip the
     height animation needs: trimmed text boxes end at the baseline. */
  .rows {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    overflow: hidden;
    padding-left: calc(10px + var(--spacing-n8));
    padding-block: 6px;
    margin-block: -6px;
  }
</style>
