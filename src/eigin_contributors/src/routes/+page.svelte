<script lang="ts">
  import { LinkButton } from "@eigin/ui";
  import CallResultsSummary from "#lib/CallResultsSummary.svelte";
  import AwardSummary from "#lib/AwardSummary.svelte";
  import CallTags from "#lib/CallTags.svelte";
  let { data } = $props();
</script>

<section class="portal-hero">
  <div class="container portal-hero-inner">
    <p class="eyebrow t-miniLabel">For contributors</p>
    <h1 class="t-display hero-title">Good thinking,<br />shared credit.</h1>
    <p class="t-standfirstLarge intro">
      Help us build the personal AI that's private, safe, and ours. We fund
      contributions and publish the work with credit to you.
    </p>
    <LinkButton href="/guides/process" label="How it works" variant="outline" />
  </div>
</section>
<section
  id="open-calls"
  class="container section"
  aria-labelledby="open-calls-title"
>
  <h2 id="open-calls-title" class="t-titleL">Open calls</h2>
  {#each data.calls as call (call.slug)}
    <div class="call-card">
      <div class="call-copy">
        <CallTags />
        <h3 class="t-titleM">
          <a href="/calls/{call.slug}">{call.title}</a>
        </h3>
        <p class="t-standfirst">{call.summary}</p>
        <LinkButton
          href="/calls/{call.slug}"
          label="Read the call"
          variant="outline"
        />
      </div>
      <AwardSummary {call} />
    </div>
  {:else}
    <p class="t-standfirst spaced">There are no open calls right now.</p>
  {/each}
</section>

{#if data.previous.entries.length || data.previous.page > 1}
  <section
    id="previous-calls"
    class="container section"
    aria-labelledby="previous-calls-title"
  >
    <h2 id="previous-calls-title" class="t-titleL">Previous calls</h2>
    {#each data.previous.entries as call}
      <article class="call-card">
        <div class="call-copy">
          <CallTags status={call.publishedAt ? "Completed" : "Closed"} />
          <h3 class="t-titleM">
            <a href={`/calls/${call.slug}`}>{call.title}</a>
          </h3>
          <p class="t-standfirst">{call.summary}</p>
          <LinkButton
            href={`/calls/${call.slug}`}
            label={call.publishedAt ? "Read the results" : "Read the call"}
            variant="outline"
          />
        </div>
        <CallResultsSummary {call} />
      </article>
    {/each}
    <nav class="actions spaced" aria-label="Previous calls pages">
      {#if data.previous.page > 1}<a
          class="t-body"
          href={`/?previousPage=${data.previous.page - 1}#previous-calls`}
          >Previous</a
        >{/if}
      {#if data.previous.hasNext}<a
          class="t-body"
          href={`/?previousPage=${data.previous.page + 1}#previous-calls`}
          >Next</a
        >{/if}
    </nav>
  </section>
{/if}
