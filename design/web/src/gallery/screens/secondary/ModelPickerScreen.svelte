<script lang="ts">
  import { ContentGroup, Disclosure, Icon, Row, SearchField } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import { EmptyState, LoadingState } from "@lib";

  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  let screenState = $state("ready");
  useStageControls(() => controls);
  let query = $state("");
  let selected = $state("auto");
  const models = [
    { name: "Claude Opus 4.6", id: "claude-opus-4-6", detail: "$$$ · 1M context" },
    { name: "Claude Sonnet 4.6", id: "claude-sonnet-4-6", detail: "$$ · 1M context" },
    { name: "Claude Haiku 4.5", id: "claude-haiku-4-5", detail: "$ · 200K context" },
    { name: "Claude Opus 4.1", id: "claude-opus-4-1", detail: "$$$ · 200K context" },
    { name: "Claude Sonnet 4.5", id: "claude-sonnet-4-5", detail: "$$ · 200K context" },
    { name: "Claude Sonnet 4", id: "claude-sonnet-4", detail: "$$ · 200K context" },
  ];
  const matches = (model: (typeof models)[number]) =>
    `${model.name} ${model.id}`.toLowerCase().includes(query.trim().toLowerCase());
  const recommended = $derived(models.slice(0, 3).filter(matches));
  const other = $derived(models.slice(3).filter(matches));
</script>

{#snippet controls()}<OptionSelector
    options={["ready", "loading", "empty"]}
    bind:value={screenState}
  />{/snippet}

<SecondaryScreen title="Model">
  {#if screenState === "loading"}
    <LoadingState title="Finding models" />
  {:else if screenState === "empty"}
    <EmptyState
      icon="functional/sparkles"
      title="No models available"
      description="This provider hasn’t returned any models. Check its connection in Settings."
    />
  {:else}
    <SearchField bind:value={query} placeholder="Search models" />
    {#if !query.trim()}
      <ContentGroup footnote="Auto follows the highest-ranked available model from this provider.">
        <Row title="Auto" description="Claude Opus 4.6" onclick={() => (selected = "auto")}>
          {#snippet trailing()}{#if selected === "auto"}<span class="selection-mark"
                ><Icon name="functional/check" size={20} /></span
              >{/if}{/snippet}
        </Row>
      </ContentGroup>
    {/if}
    {#if recommended.length}
      <ContentGroup label="Recommended">
        {#each recommended as model (model.id)}
          <Row title={model.name} description={model.detail} onclick={() => (selected = model.id)}>
            {#snippet trailing()}{#if selected === model.id}<span class="selection-mark"
                  ><Icon name="functional/check" size={20} /></span
                >{/if}{/snippet}
          </Row>
        {/each}
      </ContentGroup>
    {/if}
    {#if other.length}
      {#if query.trim()}
        <ContentGroup label="Other models">{@render otherRows()}</ContentGroup>
      {:else}
        <Disclosure title="All models" description={`${other.length} more models`}>
          {@render otherRows()}
        </Disclosure>
      {/if}
    {/if}
    {#if !recommended.length && !other.length}
      <EmptyState
        icon="functional/search"
        title="No matching models"
        description={`Try another name or model ID instead of “${query}”.`}
        action="Clear search"
        onclick={() => (query = "")}
      />
    {/if}
  {/if}
</SecondaryScreen>

{#snippet otherRows()}
  {#each other as model (model.id)}
    <Row title={model.name} description={model.detail} onclick={() => (selected = model.id)}>
      {#snippet trailing()}{#if selected === model.id}<span class="selection-mark"
            ><Icon name="functional/check" size={20} /></span
          >{/if}{/snippet}
    </Row>
  {/each}
{/snippet}

<style>
  .selection-mark {
    display: inline-flex;
    color: var(--color-icon-standard-base);
  }
</style>
