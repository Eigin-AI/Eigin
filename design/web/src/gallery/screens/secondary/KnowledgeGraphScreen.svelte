<script lang="ts">
  import { untrack } from "svelte";
  import {
    ActionButton,
    Button,
    ContentGroup,
    EmptyState,
    LoadingState,
    NavigationHeader,
    Row,
    SegmentedControl,
    Sheet,
  } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  import KnowledgeDetailScreen from "./KnowledgeDetailScreen.svelte";
  import GraphCanvas from "./graph/GraphCanvas.svelte";
  import { entityByID, neighbors } from "./graph/sampleGraph";

  let scenario = $state("arrival");
  let replay = $state(0);
  let arriving = $state(true);
  let focusID = $state("user");
  let arrivedFrom = $state<string | null>(null);
  let page = $state(0);
  let capacity = $state(6);
  let details = $state(false);
  let fullDetails = $state(false);
  const center = $derived(entityByID.get(focusID)!);
  // Keep the arrival connection on the first page as a route back.
  const related = $derived.by(() => {
    const connections = neighbors(focusID);
    const previous = connections.find((entity) => entity.id === arrivedFrom);
    return previous
      ? [previous, ...connections.filter((entity) => entity.id !== arrivedFrom)]
      : connections;
  });
  const pages = $derived(Math.max(1, Math.ceil(related.length / capacity)));
  const visible = $derived(related.slice(page * capacity, (page + 1) * capacity));
  const loading = $derived(arriving || scenario === "loading");
  useStageControls(() => controls);

  $effect(() => {
    const current = scenario;
    void replay;
    untrack(() => {
      focusID = current === "isolated" ? "note" : "user";
      arrivedFrom = null;
      page = 0;
      details = false;
      fullDetails = false;
      arriving = current === "arrival";
    });
    if (current === "arrival") {
      const timer = setTimeout(() => (arriving = false), 650);
      return () => clearTimeout(timer);
    }
  });

  function focus(id: string) {
    if (id === focusID) return;
    arrivedFrom = focusID;
    focusID = id;
    page = 0;
  }
  function home() {
    arrivedFrom = null;
    focusID = "user";
    page = 0;
  }
  function resize(count: number) {
    if (count !== capacity) {
      capacity = count;
      page = 0;
    }
  }
</script>

{#snippet controls()}
  <OptionSelector
    options={["arrival", "ready", "loading", "empty", "isolated"]}
    bind:value={scenario}
  />
  <Button
    label="Replay arrival"
    variant="secondary"
    size="small"
    onclick={() => {
      scenario = "arrival";
      replay += 1;
    }}
  />
{/snippet}

<div class="graph-screen">
  {#if fullDetails}
    <KnowledgeDetailScreen entity={center} onBack={() => (fullDetails = false)} />
  {:else}
    <NavigationHeader title="Knowledge">
      {#snippet leading()}<ActionButton
          icon="functional/arrow/left"
          label="Back to agent"
          variant="open"
          size="medium"
          onclick={() => (location.hash = "#/screens/agent")}
        />{/snippet}
    </NavigationHeader>
    <div class="view-mode">
      <SegmentedControl
        segments={[
          { value: "graph", label: "Graph" },
          { value: "list", label: "List" },
        ]}
        selection="graph"
        onSelect={(value) => {
          if (value === "list") location.hash = "#/screens/knowledge-list";
        }}
      />
    </div>
    {#if loading}
      <LoadingState title="Loading graph" />
    {:else if scenario === "empty"}
      <EmptyState
        icon="functional/asterix"
        title="Knowledge starts here"
        description="As you talk, your agent remembers people, preferences and things that matter to you."
      />
    {:else}
      <div class="explorer">
        <GraphCanvas
          {center}
          related={visible}
          onSelect={focus}
          onDetails={() => (details = true)}
          onCapacity={resize}
        />
        <div class="graph-controls">
          <div class="pagination">
            {#if pages > 1}
              <ActionButton
                icon="functional/chevron/left"
                label="Previous relationships"
                variant="open"
                size="small"
                disabled={page === 0}
                onclick={() => (page -= 1)}
              />
            {/if}
            <span class="t-note" aria-live="polite"
              >{related.length === 0
                ? "No connections yet"
                : pages > 1
                  ? `${page * capacity + 1}–${Math.min((page + 1) * capacity, related.length)} of ${related.length} connections`
                  : `${related.length} ${related.length === 1 ? "connection" : "connections"}`}</span
            >
            {#if pages > 1}
              <ActionButton
                icon="functional/chevron/right"
                label="Next relationships"
                variant="open"
                size="small"
                disabled={page + 1 >= pages}
                onclick={() => (page += 1)}
              />
            {/if}
          </div>
          <div class="navigation">
            {#if focusID !== "user" || page !== 0}
              <Button label="Back to you" variant="open" size="small" onclick={home} />
            {/if}
          </div>
        </div>
      </div>
    {/if}
    <Sheet
      bind:open={details}
      title={center.name}
      description={center.description &&
        (center.description.length > 140
          ? `${center.description.slice(0, 139).trimEnd()}…`
          : center.description)}
    >
      {#snippet primary()}
        <div class="detail-content">
          <ContentGroup>
            <Row
              title="View full details"
              onclick={() => {
                details = false;
                fullDetails = true;
              }}
            />
          </ContentGroup>
          <ContentGroup label="Connections">
            {#if related.length}
              {#each related as entity (entity.id)}<Row
                  title={entity.name}
                  onclick={() => {
                    details = false;
                    focus(entity.id);
                  }}
                />{/each}
            {:else}<Row title="No connections yet" accessory="none" />{/if}
          </ContentGroup>
        </div>
      {/snippet}
    </Sheet>
  {/if}
</div>

<style>
  .graph-screen {
    container-type: size;
    display: flex;
    flex-direction: column;
    position: relative;
    height: 100%;
    min-height: 0;
    overflow: hidden;
    background: var(--color-surface-standard-base);
  }
  .view-mode {
    flex: none;
    padding: 0 var(--spacing-n16) var(--spacing-n8);
  }
  .explorer {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    padding: 0 var(--spacing-n8) max(var(--spacing-n16), var(--eigin-safe-area-bottom, 0px));
  }
  .graph-controls {
    flex: none;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0;
    color: var(--color-text-standard-muted);
  }
  .navigation,
  .pagination {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-n8);
    min-width: 0;
  }
  /* Reserve the actual button heights even when controls are absent. */
  .pagination {
    height: var(--sizing-button-action-small);
  }
  .navigation {
    height: var(--sizing-button-action-extraSmall);
    min-width: 168px;
    gap: var(--spacing-n16);
    color: var(--color-text-standard-muted);
  }
  .detail-content {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n16);
  }
  .graph-screen :global(.header .description) {
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 4;
    line-clamp: 4;
    overflow: hidden;
    overflow-wrap: anywhere;
  }
  @container (max-height: 450px) {
    .graph-screen :global(.nav-header) {
      padding-top: var(--spacing-n32);
      padding-bottom: 0;
    }
    .graph-screen :global(.nav-header .frame) {
      height: var(--spacing-n32);
    }
    .graph-controls {
      flex-direction: row;
      justify-content: space-evenly;
      gap: var(--spacing-n8);
    }
  }
</style>
