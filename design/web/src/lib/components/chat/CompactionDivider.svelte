<script lang="ts">
  import Icon from "../icon/Icon.svelte";

  interface Props {
    /** 0–1 while compacting, undefined once it has finished. */
    progress?: number;
    /** Available once compaction is done; tapping the divider reveals it. */
    summary?: string;
  }

  const { progress, summary }: Props = $props();

  const isCompacting = $derived(progress !== undefined);
  const hasSummary = $derived(summary !== undefined && !isCompacting);
  const fill = $derived(Math.min(Math.max(progress ?? 0, 0), 1));

  let expanded = $state(false);

  /** The summary arrives as markdown; only its heading marks would show here. */
  const cleanedSummary = $derived(
    (summary ?? "")
      .split("\n")
      .map((line) => line.replace(/^#{1,6}\s*/, ""))
      .join("\n"),
  );
</script>

<div class="compaction">
  {#snippet line()}
    <span class="track">
      {#if isCompacting}
        <span class="fill" style:width="{fill * 100}%"></span>
      {/if}
    </span>

    <span class="label t-miniLabel">
      {isCompacting ? "Compacting…" : "Conversation summarized"}
      {#if hasSummary}
        <span class="chevron" class:up={expanded}>
          <Icon name="functional/chevron/down" size={16} />
        </span>
      {/if}
    </span>
  {/snippet}

  <!-- The label sits on the line, masking it, so the fill runs behind the text.
       Only a divider with a summary to show is tappable. -->
  {#if hasSummary}
    <button
      class="line tappable"
      type="button"
      aria-expanded={expanded}
      onclick={() => (expanded = !expanded)}
    >
      {@render line()}
    </button>
  {:else}
    <div class="line" role="separator">
      {@render line()}
    </div>
  {/if}

  <!-- Grid rows animate where height: auto can't, so the summary unfolds. -->
  {#if summary}
    <div class="summary-fold" class:open={expanded}>
      <div>
        <p class="summary t-miniLabel">{cleanedSummary}</p>
      </div>
    </div>
  {/if}
</div>

<style>
  /* Inset like the tool groups and brand messages it sits between. */
  .compaction {
    box-sizing: border-box;
    width: 100%;
    display: flex;
    flex-direction: column;
    padding: var(--spacing-n4) var(--chat-px-large);
  }

  .line {
    display: grid;
    align-items: center;
    justify-items: center;
    padding: 0;
    border: 0;
    background: none;
    font: inherit;
    color: inherit;
    text-align: inherit;
  }

  /* Line and label share one cell, so the label masks the rule behind it. */
  .line > * {
    grid-area: 1 / 1;
  }

  .tappable {
    cursor: pointer;
  }

  .track {
    position: relative;
    width: 100%;
    height: 2px;
    display: flex;
    align-items: center;
  }

  .track::before {
    content: "";
    width: 100%;
    height: 1px;
    background: var(--color-border-standard-base);
  }

  /* The fill is the only thing that moves; the chaser keeps it travelling. */
  .fill {
    position: absolute;
    left: 0;
    height: 2px;
    background: var(--color-accent);
    transition: width var(--motion-normal) var(--motion-easing-smooth);
  }

  /* Positioned, so it paints above the (positioned) track it masks. */
  .label {
    position: relative;
    display: flex;
    align-items: center;
    gap: var(--spacing-n4);
    padding: 0 var(--spacing-n8);
    background: var(--color-surface-standard-base);
    color: var(--color-text-standard-muted);
    text-box: normal;
  }

  .chevron {
    display: flex;
    transition: transform var(--motion-fast) var(--motion-easing-smooth);
  }

  .up {
    transform: rotate(180deg);
  }

  .summary-fold {
    display: grid;
    grid-template-rows: 0fr;
    opacity: 0;
    transition:
      grid-template-rows var(--motion-normal) var(--motion-easing-smooth),
      opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .summary-fold.open {
    grid-template-rows: 1fr;
    opacity: 1;
  }

  .summary-fold > div {
    overflow: hidden;
  }

  .summary {
    margin: 0;
    padding: var(--spacing-n8) var(--spacing-n8) 0;
    color: var(--color-text-standard-muted);
    white-space: pre-wrap;
    text-box: normal;
  }
</style>
