<script lang="ts">
  import { LinkButton } from "@eigin/ui";
  import AwardSummary from "#lib/AwardSummary.svelte";
  import CallBrief from "#lib/CallBrief.svelte";
  import CallTags from "#lib/CallTags.svelte";
  let { data } = $props();
</script>

<svelte:head><title>{data.call.title} · Eigin</title></svelte:head>
<section class="container section">
  <div class="page-intro">
    <CallTags status={data.upcoming ? "Upcoming" : undefined} />
    <h1 class="t-display page-title">{data.call.title}</h1>
    <p class="t-standfirst intro">{data.call.summary}</p>
  </div>
  <div class="split spaced">
    <article class="guide-content"><CallBrief text={data.brief} /></article>
    <aside
      class="stack funding-sidebar"
      aria-label="Call funding"
      data-sveltekit-reload={!data.user ? true : undefined}
    >
      <AwardSummary call={data.call} />
      {#if data.upcoming}
        <p class="t-body">
          Submissions open {new Date(data.call.opensAt).toLocaleString(
            "en-GB",
            {
              timeZone: data.call.displayTimezone,
              dateStyle: "long",
              timeStyle: "short",
            },
          )} Copenhagen time.
        </p>
      {:else}<LinkButton
          href={data.submitted && !data.closed
            ? `/calls/${data.call.slug}/submission?edit=1`
            : `/calls/${data.call.slug}/submission`}
          label={data.submitted
            ? data.closed
              ? "View your spec"
              : "Edit your spec"
            : data.closed
              ? "Submissions closed"
              : "Submit your spec"}
          variant="outline"
        />{/if}
      <section class="call-discussion" aria-labelledby="call-discussion-title">
        <h2 id="call-discussion-title" class="t-titleXS">
          Questions about this call?
        </h2>
        <div class="call-discussion-links t-body">
          {#if data.call.issueUrl}
            <a href={data.call.issueUrl} target="_blank" rel="noopener"
              >Discuss on GitLab</a
            >
          {/if}
          <a href="https://chat.eigin.ai" target="_blank" rel="noopener"
            >Chat on Matrix</a
          >
        </div>
      </section>
    </aside>
  </div>
</section>

<style>
  .call-discussion {
    border-top: 1px solid var(--color-border-standard-base);
    padding-top: var(--spacing-n24);
  }
  .call-discussion-links {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n12);
    margin-top: var(--spacing-n16);
  }
</style>
