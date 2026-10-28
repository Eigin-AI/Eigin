<script lang="ts">
  import { Icon, Tag } from "@eigin/ui";
  import type { FeatureContent } from "../content/home/types";
  import TeamDiagram from "./diagrams/TeamDiagram.svelte";
  import AnimatedIllustration from "./AnimatedIllustration.svelte";
  import ChatPlayback from "./chat/ChatPlayback.svelte";
  let { feature }: { feature: FeatureContent } = $props();
  let current = $state(0);
  const playback = $derived(feature.examples && feature.chat ? feature.examples : undefined);
</script>

<section
  id={feature.id}
  class="feature-section"
  class:team-section={feature.id === "teams"}
  data-color-scheme="light"
  aria-labelledby="{feature.id}-title"
>
  <div class="container section-space content-grid feature-grid">
    <div class="feature-copy">
      <div class="feature-label">
        <p class="t-miniLabel eyebrow muted">{feature.label}</p>
        {#if feature.status}<Tag label={feature.status} disabled />{/if}
      </div>
      <h2 class="t-display section-title" id="{feature.id}-title">{feature.title}</h2>
      <p class="t-standfirst section-intro muted">{feature.body}</p>
      {#if playback}
        <ul class="feature-list feature-tabs t-standfirst" aria-label={feature.chat?.examples}>
          {#each playback as example, index}
            <li>
              <button
                type="button"
                aria-pressed={current === index}
                aria-controls="{feature.id}-chat"
                onclick={() => (current = index)}
              >
                <span class="feature-bullet-icon" aria-hidden="true"
                  ><Icon name="functional/arrow/right" size={12} /></span
                ><span class="feature-tab-label">
                  <span>{example.label}</span>
                  <strong aria-hidden="true">{example.label}</strong>
                </span>
              </button>
            </li>
          {/each}
        </ul>
      {:else}
        <ul class="feature-list t-standfirst">
          {#each feature.bullets ?? [] as bullet}
            <li>
              <span class="feature-bullet-icon" aria-hidden="true"
                ><Icon name="functional/arrow/right" size={12} /></span
              ><span>{bullet}</span>
            </li>
          {/each}
        </ul>
      {/if}
    </div>
    {#if playback && feature.chat}
      <ChatPlayback
        examples={playback}
        labels={feature.chat}
        bind:index={current}
        id="{feature.id}-chat"
      />
    {:else if feature.diagram}
      <AnimatedIllustration class="team-diagram" labels={feature.diagram} controlVariant="open">
        {#snippet children(active)}
          <TeamDiagram labels={feature.diagram!} {active} />
        {/snippet}
      </AnimatedIllustration>
    {/if}
  </div>
</section>
