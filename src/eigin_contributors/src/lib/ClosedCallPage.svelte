<script lang="ts">
  import ResultsPage from "./ResultsPage.svelte";
  import CallBrief from "./CallBrief.svelte";
  import CallTags from "./CallTags.svelte";
  import AwardSummary from "./AwardSummary.svelte";
  import type { PublicCall, PublicResult } from "./publication.ts";
  let {
    result,
    call,
  }: { result: PublicResult | null; call: PublicCall | null } = $props();
</script>

<svelte:head
  ><title>{result?.title ?? call?.title} · Eigin contributors</title
  ></svelte:head
>
<section class="container section">
  {#if result}
    <ResultsPage
      title={result.title}
      summary={result}
      copy={result.copy}
      publicPage
      links={{
        selected: `/calls/${result.slug}/specs/selected`,
        runnerUp: `/calls/${result.slug}/specs/runner-up`,
      }}
    />
  {:else if call}
    <div class="page-intro">
      <CallTags status="Closed" />
      <h1 class="t-display page-title">{call.title}</h1>
      <p class="t-standfirst intro">{call.summary}</p>
      <p class="t-body spaced">Results forthcoming</p>
    </div>
    <div class="split spaced">
      <article class="guide-content"><CallBrief text={call.brief} /></article>
      <aside aria-label="Call funding"><AwardSummary {call} closed /></aside>
    </div>
  {/if}
</section>
