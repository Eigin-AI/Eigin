<script lang="ts">
  import { CardSurface, LinkButton } from "@eigin/ui";
  import CallTags from "./CallTags.svelte";
  import type { ResultsCopy } from "./results-copy.ts";
  import type { PublicSpec } from "./publication.ts";
  let {
    title,
    summary,
    copy,
    links,
    publicPage = false,
  }: {
    title: string;
    summary: {
      currency: string;
      selected: Omit<PublicSpec, "markdown">;
      runnerUp: Omit<PublicSpec, "markdown">;
    };
    copy: ResultsCopy;
    links: { selected: string; runnerUp: string };
    publicPage?: boolean;
  } = $props();
  const amount = (minor: number) =>
    new Intl.NumberFormat("en", {
      style: "currency",
      currency: summary.currency,
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(minor / 100);
  const specs = $derived([
    {
      place: "selected",
      href: links.selected,
      designation: "Selected spec",
      entry: summary.selected,
      description: copy.selectedSummary,
    },
    {
      place: "runner-up",
      href: links.runnerUp,
      designation: "Runner-up spec",
      entry: summary.runnerUp,
      description: copy.runnerUpSummary,
    },
  ]);
</script>

<div
  class="results-page"
  aria-label={publicPage ? "Call results" : "Results page preview"}
>
  <div class="page-intro">
    <CallTags status="Completed" />
    <svelte:element this={publicPage ? "h1" : "h2"} class="t-display page-title"
      >{title}</svelte:element
    >
    <p class="t-standfirstLarge intro results-text">{copy.introduction}</p>
  </div>
  <section class="selected-specs" aria-label="The funded specs">
    <div class="section-heading">
      <h3 class="t-titleM">The funded specs</h3>
    </div>
    <div class="selected-spec-grid">
      {#each specs as spec}
        <CardSurface padding={32}>
          <article
            class="selected-spec-card"
            aria-label={spec.designation + ": " + spec.entry.author}
          >
            <div class="selected-spec-award">
              <span class="call-tag t-tag">{spec.designation}</span><span
                class="t-titleM">{amount(spec.entry.amountMinor)}</span
              >
            </div>
            <div class="selected-author">
              <p class="t-miniLabel eyebrow">A specification by</p>
              <h4 class="t-titleL">{spec.entry.author}</h4>
              <h5 class="t-titleS">{spec.entry.title}</h5>
            </div>
            <p class="t-standfirst results-text spec-description">
              {spec.description}
            </p>
            <LinkButton
              href={spec.href}
              label={spec.place === "selected"
                ? "Read the selected spec"
                : "Read the runner-up spec"}
              variant="outline"
            />
          </article>
        </CardSurface>
      {/each}
    </div>
  </section>
  <div class="content-row results-context">
    <h3 class="t-titleM">What we learned</h3>
    <div class="prose">
      {#each copy.learned.split(/\n\s*\n/) as paragraph}<p class="results-text">
          {paragraph}
        </p>{/each}
    </div>
  </div>
</div>

<style>
  .selected-spec-card {
    gap: var(--spacing-n32);
  }
  .selected-author {
    gap: var(--spacing-n16);
  }
  .selected-author h5 {
    margin: 0;
  }

  .page-title {
    text-transform: uppercase;
  }
  .results-text {
    white-space: pre-line;
    overflow-wrap: anywhere;
  }
  .results-page {
    margin-block: var(--spacing-n32);
  }
</style>
