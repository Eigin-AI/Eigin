<script lang="ts">
  import { ContentGroup, EmptyState, LoadingState, Row, SegmentedControl } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import KnowledgeCategoryScreen from "./KnowledgeCategoryScreen.svelte";
  import KnowledgeDetailScreen from "./KnowledgeDetailScreen.svelte";
  import { entities, type GraphEntity } from "./graph/sampleGraph";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  let screenState = $state("ready");
  let selected = $state<GraphEntity>();
  let category = $state<(typeof groups)[number]>();
  useStageControls(() => controls);
  const groups = [
    { title: "Actors", kind: "Actor" },
    { title: "Things", kind: "Thing" },
    { title: "Facts", kind: "Fact" },
    { title: "Outputs", kind: "Output" },
    { title: "Notes", kind: "Note" },
  ];
</script>

{#snippet controls()}<OptionSelector
    options={["ready", "loading", "empty"]}
    bind:value={screenState}
  />{/snippet}

{#if selected}
  <KnowledgeDetailScreen entity={selected} onBack={() => (selected = undefined)} />
{:else if category}
  <KnowledgeCategoryScreen
    kind={category.kind}
    title={category.title}
    onBack={() => (category = undefined)}
  />
{:else}
  <SecondaryScreen title="Knowledge">
    {#if screenState === "loading"}
      <LoadingState title="Loading knowledge" />
    {:else if screenState === "empty"}
      <EmptyState
        icon="functional/asterix"
        title="Knowledge starts here"
        description="As you talk, your agent remembers people, preferences and things that matter to you."
      />
    {:else}
      <SegmentedControl
        segments={[
          { value: "graph", label: "Graph" },
          { value: "list", label: "List" },
        ]}
        selection="list"
        onSelect={(value) =>
          (location.hash = value === "graph" ? "#/screens/knowledge" : "#/screens/knowledge-list")}
      />
      {#each groups as group (group.kind)}
        {@const matches = entities.filter((entity) => entity.kind === group.kind)}
        <ContentGroup label={group.title}>
          {#each matches.slice(0, 4) as entity (entity.id)}
            <Row
              title={entity.name}
              description={entity.description}
              descriptionLineLimit={2}
              onclick={() => (selected = entity)}
            />
          {/each}
          {#if matches.length > 4}
            <Row
              title={`Show all ${group.title.toLowerCase()}`}
              value={String(matches.length)}
              tone="muted"
              onclick={() => (category = group)}
            />
          {/if}
        </ContentGroup>
      {/each}
    {/if}
  </SecondaryScreen>
{/if}
