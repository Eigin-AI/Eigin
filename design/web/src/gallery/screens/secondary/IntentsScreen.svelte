<script lang="ts">
  import { ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import { EmptyState } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  let scenario = $state("active");
  useStageControls(() => controls);

  import IntentDetailScreen from "./IntentDetailScreen.svelte";
  import { intents, type GalleryIntent } from "./intentsData";
  let selected = $state<GalleryIntent>();
</script>

{#snippet controls()}<OptionSelector
    options={["active", "empty"]}
    bind:value={scenario}
  />{/snippet}

{#if selected}
  <IntentDetailScreen intent={selected} onBack={() => (selected = undefined)} />
{:else}
  <SecondaryScreen title="Intents">
    {#if scenario === "empty"}
      <EmptyState
        icon="functional/sparkles"
        title="Nothing to follow up on"
        description="Goals and plans your agent is keeping track of will appear here."
      />
    {:else}
      <ContentGroup footnote="Your agent keeps these goals in mind across conversations.">
        {#each intents as intent (intent.content)}
          <Row
            title={intent.content}
            description={intent.cue}
            accessory="none"
            onclick={() => (selected = intent)}
          />
        {/each}
      </ContentGroup>
    {/if}
  </SecondaryScreen>
{/if}
