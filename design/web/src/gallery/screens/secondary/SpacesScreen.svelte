<script lang="ts">
  import { ActionButton, ContentGroup, Row } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import { EmptyState } from "@lib";
  let scenario = $state("populated");
  useStageControls(() => controls);
</script>

{#snippet controls()}<OptionSelector
    options={["populated", "empty"]}
    bind:value={scenario}
  />{/snippet}
<SecondaryScreen title="Spaces" back="chat-list">
  {#snippet trailing()}<ActionButton
      icon="functional/plus"
      variant="open"
      size="medium"
      label="New space"
      onclick={() => (location.hash = "#/screens/space-detail")}
    />{/snippet}
  {#if scenario === "empty"}
    <EmptyState
      icon="brand/security"
      title="No spaces yet"
      description="Group related chats in a space, with instructions of their own."
      action="Create space"
      onclick={() => (location.hash = "#/screens/space-detail")}
    />
  {:else}
    <ContentGroup>
      <Row
        title="🌿 Everyday"
        description="12 chats"
        onclick={() => (location.hash = "#/screens/space-detail")}
      />
      <Row
        title="🚆 Travel"
        description="4 chats"
        onclick={() => (location.hash = "#/screens/space-detail")}
      />
      <Row
        title="✍️ Journal"
        description="Private · 8 chats"
        onclick={() => (location.hash = "#/screens/space-detail")}
      />
    </ContentGroup>
  {/if}
</SecondaryScreen>
