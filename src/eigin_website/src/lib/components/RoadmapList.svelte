<script lang="ts">
  import type { Locale } from "../locales";
  import type { RoadmapItem } from "../content/roadmap/types";

  let {
    items,
    locale,
    nested = false,
  }: {
    items: RoadmapItem[];
    locale: Locale;
    /** Release items sit below a month heading. */
    nested?: boolean;
  } = $props();
</script>

<ul class="roadmap-list">
  {#each items as item (item.id)}
    {@const text = item.copy[locale] ?? item.copy.en}
    <li id="roadmap-{item.id}" lang={item.copy[locale] ? locale : "en"}>
      <div class="roadmap-item-heading">
        <svelte:element this={nested ? "h4" : "h3"} class="t-titleS">{text.title}</svelte:element>
        {#if item.version?.href}
          <a class="eigin-btn secondary tag roadmap-version" href={item.version.href}
            ><span class="t-tag">{item.version.label}</span></a
          >
        {:else if item.version}
          <span class="eigin-btn secondary tag roadmap-version"
            ><span class="t-tag">{item.version.label}</span></span
          >
        {/if}
      </div>
      {#if text.description}<p class="t-body muted">{text.description}</p>{/if}
    </li>
  {/each}
</ul>
