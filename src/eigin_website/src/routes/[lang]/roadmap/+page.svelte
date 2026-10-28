<script lang="ts">
  import PageHead from "#lib/components/PageHead.svelte";
  import SectionHeading from "#lib/components/SectionHeading.svelte";
  import { Icon } from "@eigin/ui";
  import SiteHeader from "#lib/components/SiteHeader.svelte";
  import SiteFooter from "#lib/components/SiteFooter.svelte";
  import RoadmapList from "#lib/components/RoadmapList.svelte";
  import type { PageData } from "./$types";

  let { data }: { data: PageData } = $props();
  const copy = $derived(data.copy);
  const statuses = ["active", "planned"] as const;
</script>

<PageHead title={copy.title} description={copy.description} locale={data.locale} path="roadmap/" />

<a class="skip t-body" href="#main">{data.site.skip}</a>
<SiteHeader locale={data.locale} copy={data.site} />
<main id="main" class="roadmap-page">
  <div class="container section-space roadmap-inner">
    <div class="roadmap-intro">
      <h1 class="t-display roadmap-title">{copy.heading}</h1>
      <p class="t-standfirstLarge muted">{copy.introduction}</p>
      <div class="roadmap-links t-body">
        <a class="arrow-link arrow-link-label" href="https://code.eigin.ai/dev/eigin">
          <span class="arrow-link-text">{copy.sourceLabel}</span><span
            class="arrow-link-icon"
            aria-hidden="true"><Icon name="functional/arrow/up_right" size={16} /></span
          >
        </a>
        <a class="arrow-link arrow-link-label" href="https://chat.eigin.ai">
          <span class="arrow-link-text">{copy.communityLabel}</span><span
            class="arrow-link-icon"
            aria-hidden="true"><Icon name="functional/arrow/up_right" size={16} /></span
          >
        </a>
      </div>
    </div>

    {#each statuses as key}
      <section class="content-grid roadmap-status" aria-labelledby="roadmap-{key}-title">
        <SectionHeading
          class="roadmap-status-label"
          id="roadmap-{key}-title"
          title={copy[key].title}
        />
        <div class="roadmap-status-content">
          {#if data.roadmap[key].length}
            <RoadmapList items={data.roadmap[key]} locale={data.locale} />
          {:else}
            <p class="t-body muted">{copy.empty}</p>
          {/if}
        </div>
      </section>
    {/each}

    <section class="content-grid roadmap-status" aria-labelledby="roadmap-launched-title">
      <SectionHeading
        class="roadmap-status-label"
        id="roadmap-launched-title"
        title={copy.launched.title}
      />
      <div class="roadmap-status-content roadmap-releases">
        {#each data.roadmap.launched as release (release.id)}
          <div>
            {#if release.period}
              <h3 class="t-miniLabel muted roadmap-period" id="release-{release.id}">
                {release.period[data.locale]}
              </h3>
            {/if}
            <RoadmapList
              items={release.items}
              locale={data.locale}
              nested={Boolean(release.period)}
            />
          </div>
        {:else}
          <p class="t-body muted">{copy.empty}</p>
        {/each}
      </div>
    </section>
  </div>
</main>
<SiteFooter locale={data.locale} copy={data.site} />
