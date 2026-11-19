<script lang="ts">
  import { page } from "$app/state";
  import { LinkButton } from "@eigin/ui";
  import CallTags from "#lib/CallTags.svelte";
  import type { LayoutProps } from "./$types";
  let { data, children }: LayoutProps = $props();
  const selectionRoot = $derived(
    page.url.pathname === `/review/calls/${data.call.slug}/selection`,
  );
  const selectionRoute = $derived(
    selectionRoot ||
      page.url.pathname.startsWith(
        `/review/calls/${data.call.slug}/selection/`,
      ),
  );
  const heading = $derived.by(() => {
    if (
      page.url.pathname === `/review/calls/${data.call.slug}/selection/publish`
    )
      return "Publish results";
    if (!selectionRoot) return "Read the specs.";
    if (data.recordedSelection || page.data.recorded)
      return "Selection confirmed";
    if (page.form?.confirmation) return "Preview the results";
    if (page.form?.editing?.summary || page.data.summary)
      return "Write the results";
    return "Choose recipients";
  });
</script>

<svelte:head><title>{heading} · Eigin</title></svelte:head>
<section class="container section">
  <nav class="actions" aria-label="Review navigation">
    <a href="/review">All calls</a>
    {#if data.call.briefHref}<a href={`/review/calls/${data.call.slug}`}
        >Read the call</a
      >{/if}
  </nav>
  <div class="page-intro">
    <CallTags status="Review" />
    <h1 class="t-display page-title">{heading}</h1>
    <p class="t-standfirstLarge intro">{data.call.title}</p>
  </div>
  {#if !data.call.contentAvailable && !selectionRoute}<p class="t-body spaced">
      The original call title and brief are unavailable. Saved submissions
      remain accessible under this call’s identifier.
    </p>{/if}
  {#if !selectionRoute}
    <div class="review-toolbar actions" data-sveltekit-reload>
      {#if data.call.status === "closed" || data.recordedSelection}
        <LinkButton
          href="/review/calls/{data.call.slug}/selection"
          label={data.recordedSelection
            ? "View selection"
            : data.hasResultsDraft
              ? "Continue results"
              : "Choose recipients"}
          variant="outline"
          size="small"
        />
      {/if}
      <LinkButton
        href="/review/calls/{data.call.slug}/archive"
        label="Download all submissions"
        variant="outline"
        size="small"
      />
    </div>
  {/if}
  {#if selectionRoute}
    <div class="selection-content spaced">{@render children()}</div>
  {:else}
    <div class="review-layout">
      <aside class="review-index" aria-label="Submission list">
        <h2 class="t-titleS review-index-heading">
          Submissions <span class="t-miniLabel review-count"
            >{data.call.submissions}</span
          >
        </h2>
        <ul class="review-list">
          {#each data.entries as entry (entry.id)}
            <li>
              <a
                class="review-entry"
                class:chosen={page.params.submissionId === entry.id}
                aria-current={page.params.submissionId === entry.id
                  ? "page"
                  : undefined}
                href="/review/calls/{data.call
                  .slug}/submissions/{entry.id}?page={data.page}"
              >
                <span class="t-titleXS review-entry-author" title={entry.author}
                  >{entry.author}</span
                >
                <span class="t-body review-entry-title" title={entry.title}
                  >{entry.title}</span
                >
              </a>
            </li>
          {:else}
            <li class="t-body">No submissions yet.</li>
          {/each}
        </ul>
        <nav class="actions review-note" aria-label="Submission pages">
          <span class="t-miniLabel">Page {data.page}</span>
          {#if data.page > 1}<a
              href="/review/calls/{data.call.slug}?page={data.page - 1}"
              >Previous</a
            >{/if}
          {#if data.hasNext}<a
              href="/review/calls/{data.call.slug}?page={data.page + 1}">Next</a
            >{/if}
        </nav>
      </aside>
      <div class="review-detail">{@render children()}</div>
    </div>
  {/if}
</section>
