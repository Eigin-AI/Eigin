<script lang="ts">
  import type { PageProps } from "./$types";
  let { data }: PageProps = $props();
  const groups = [
    { status: "open", title: "Open calls" },
    { status: "upcoming", title: "Upcoming calls" },
    { status: "closed", title: "Closed calls" },
  ];
  function deadline(value: string, timeZone: string) {
    return new Intl.DateTimeFormat("en-GB", {
      dateStyle: "medium",
      timeZone,
    }).format(new Date(value));
  }
</script>

<svelte:head><title>Review calls · Eigin</title></svelte:head>
<section class="container section">
  <div class="page-intro">
    <h1 class="t-display page-title">Review calls.</h1>
    <p class="t-standfirst intro">
      Choose a call to read its submissions. Closed calls stay available here.
    </p>
  </div>
  {#each groups as group}
    {@const calls = data.calls.filter((call) => call.status === group.status)}
    {#if calls.length}
      <section class="spaced" aria-labelledby="review-{group.status}">
        <h2 id="review-{group.status}" class="t-titleM">{group.title}</h2>
        <ul class="review-calls">
          {#each calls as call (call.slug)}
            <li>
              <a class="review-call" href="/review/calls/{call.slug}">
                <span class="t-titleS">{call.title}</span>
                <span class="review-call-meta t-body">
                  <span
                    >{call.submissions}
                    {call.submissions === 1
                      ? "submission"
                      : "submissions"}</span
                  >
                  <span
                    >{call.status === "closed" ? "Closed" : "Closes"}
                    <time datetime={call.closesAt}
                      >{deadline(call.closesAt, call.timeZone)}</time
                    ></span
                  >
                </span>
              </a>
            </li>
          {/each}
        </ul>
      </section>
    {/if}
  {/each}
  {#if !data.calls.length}<p class="t-body spaced">No calls yet.</p>{/if}
</section>

<style>
  .review-calls {
    list-style: none;
    margin: var(--spacing-n24) 0 0;
    padding: 0;
  }
  .review-call {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: var(--spacing-n24);
    padding-block: var(--spacing-n24);
    border-bottom: 1px solid var(--color-border-standard-base);
    text-decoration: none;
  }
  .review-call > .t-titleS {
    max-width: 40rem;
    overflow-wrap: anywhere;
  }
  .review-call:hover > .t-titleS {
    text-decoration: underline;
  }
  .review-call-meta {
    display: grid;
    gap: var(--spacing-n8);
    flex-shrink: 0;
  }
  @media (max-width: 760px) {
    .review-call {
      flex-direction: column;
      gap: var(--spacing-n12);
    }
  }
</style>
