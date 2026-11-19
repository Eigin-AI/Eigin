<script lang="ts">
  import Preview from "#lib/Preview.svelte";
  import DocumentIndex from "@eigin/website/DocumentIndex.svelte";
  import type { PageProps } from "./$types";
  let { data }: PageProps = $props();
</script>

<svelte:head><title>Participation terms · Eigin</title></svelte:head>
<section class="container section">
  <div class="page-intro">
    <h1 class="t-display page-title">Participation terms</h1>
  </div>
  <div class="terms-layout spaced">
    <DocumentIndex sections={data.sections} />
    <div class="guide-content terms-reading">
      <article id="participation-draft" class="stack">
        {#if data.introduction.trim()}<Preview text={data.introduction} />{/if}
        {#each data.sections as section}
          <section class="stack" aria-labelledby={section.id}>
            <h2 id={section.id} class="t-titleS" tabindex="-1">
              {section.title}
            </h2>
            <Preview text={section.body} />
          </section>
        {/each}
      </article>
    </div>
  </div>
</section>

<style>
  .terms-layout {
    display: grid;
    grid-template-columns: minmax(180px, 1fr) minmax(0, 3fr);
    align-items: start;
    gap: var(--spacing-n40);
  }
  .terms-reading {
    min-width: 0;
  }
  h2 {
    scroll-margin-top: var(--spacing-n24);
  }
  @media (max-width: 1023px) {
    .terms-layout {
      grid-template-columns: minmax(0, 1fr);
    }
  }
  @media print {
    .terms-layout {
      display: block;
    }
  }
</style>
