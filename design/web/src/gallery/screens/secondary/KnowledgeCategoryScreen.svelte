<script lang="ts">
  import { ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import KnowledgeDetailScreen from "./KnowledgeDetailScreen.svelte";
  import { entities, type GraphEntity } from "./graph/sampleGraph";
  let {
    kind = "Fact",
    title = "Facts",
    onBack,
  }: {
    kind?: string;
    title?: string;
    onBack?: () => void;
  } = $props();
  const matches = $derived(entities.filter((entity) => entity.kind === kind));
  let selected = $state<GraphEntity>();
  let visibleCount = $state(20);
</script>

<div class="category-stage">
  {#if selected}
    <div class="detail-page">
      <KnowledgeDetailScreen entity={selected} onBack={() => (selected = undefined)} />
    </div>
  {/if}
  <div class="category-page" class:inactive={!!selected} inert={!!selected}>
    <SecondaryScreen {title} back="knowledge-list" {onBack}>
      <ContentGroup>
        {#each matches.slice(0, visibleCount) as entity (entity.id)}
          <Row
            title={entity.name}
            description={entity.description}
            descriptionLineLimit={2}
            onclick={() => (selected = entity)}
          />
        {/each}
        {#if visibleCount < matches.length}
          <Row
            title={`Show ${Math.min(20, matches.length - visibleCount)} more`}
            tone="muted"
            onclick={() => (visibleCount += 20)}
          />
        {/if}
      </ContentGroup>
    </SecondaryScreen>
  </div>
</div>

<style>
  .category-stage {
    position: relative;
    height: 100%;
    min-height: 0;
  }
  .detail-page {
    position: absolute;
    inset: 0;
  }
  .inactive {
    visibility: hidden;
    pointer-events: none;
  }
  .category-page {
    height: 100%;
    min-height: 0;
  }
</style>
