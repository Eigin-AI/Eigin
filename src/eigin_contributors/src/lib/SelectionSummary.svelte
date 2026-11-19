<script lang="ts">
  import type { SelectionSummary } from "./server/selection.ts";
  let {
    summary,
    recorded = false,
  }: { summary: SelectionSummary; recorded?: boolean } = $props();
  const amount = (minor: number) =>
    new Intl.NumberFormat("en", {
      style: "currency",
      currency: summary.currency,
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(minor / 100);
</script>

<div class="selection-summary">
  {#each [{ key: "selected", label: "Selected spec", entry: summary.selected }, { key: "runner-up", label: "Runner-up spec", entry: summary.runnerUp }] as item}
    <section>
      <h3 class="t-titleS">{item.label} · {amount(item.entry.amountMinor)}</h3>
      <p class="t-titleXS">{item.entry.title}</p>
      <p class="t-body">{item.entry.author}</p>
      <a
        class="t-body"
        href={recorded
          ? `/review/calls/${summary.callSlug}/selection/${item.key}`
          : `/review/calls/${summary.callSlug}/submissions/${item.entry.submissionId}`}
        target="_blank"
        rel="noopener">Read {item.label.toLowerCase()}</a
      >
    </section>
  {/each}
</div>

<style>
  .selection-summary {
    display: grid;
    gap: var(--spacing-n24);
    margin-block: var(--spacing-n24);
  }
  section {
    background: var(--color-surface-standard-base);
    border-radius: var(--radius-card);
    padding: var(--spacing-n24);
    display: grid;
    gap: var(--spacing-n16);
    overflow-wrap: anywhere;
  }
  @media (min-width: 768px) {
    .selection-summary {
      grid-template-columns: 1fr 1fr;
    }
  }
</style>
