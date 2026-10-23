<script lang="ts">
  import { ContentGroup, EmptyState, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import DetailText from "./DetailText.svelte";
  import { entityByID, relationships, type GraphEntity } from "./graph/sampleGraph";
  import { additionalFields } from "./knowledgeData";

  let { entity = entityByID.get("train")!, onBack }: { entity?: GraphEntity; onBack?: () => void } =
    $props();
  let path = $state<string[]>([]);
  let deleted = $state(false);
  const current = $derived(path.length ? entityByID.get(path[path.length - 1])! : entity);
  const fields = $derived(additionalFields(current));
  const connections = $derived(relationships(current.id));

  function back() {
    deleted = false;
    if (path.length) path = path.slice(0, -1);
    else if (onBack) onBack();
    else location.hash = "#/screens/knowledge-list";
  }
</script>

<SecondaryScreen title="Knowledge" onBack={back}>
  {#if deleted}
    <EmptyState
      icon="functional/check_circle"
      title="Knowledge deleted"
      description="This sample knowledge has been removed for this preview."
      action="Undo preview"
      onclick={() => (deleted = false)}
    />
  {:else}
    <ContentGroup label={current.kind}>
      <Row title={current.name} accessory="none" />
      {#if current.description}<DetailText text={current.description} />{/if}
    </ContentGroup>
    <ContentGroup label="Fields">
      <Row title="ID" description={current.id} accessory="none" />
      {#each fields as [title, description] (title)}
        <Row {title} {description} accessory="none" />
      {/each}
    </ContentGroup>
    {#if current.fields.tags?.length}
      <ContentGroup label="Tags"><DetailText text={current.fields.tags.join(" · ")} /></ContentGroup
      >
    {/if}
    {#if connections.length}
      <ContentGroup label="Relationships">
        {#each connections as connection (`${connection.entity.id}:${connection.label}`)}
          <Row
            title={connection.entity.name}
            description={connection.label}
            onclick={() => {
              path = [...path, connection.entity.id];
              deleted = false;
            }}
          />
        {/each}
      </ContentGroup>
    {/if}
    <ContentGroup>
      <Row
        title="Delete knowledge"
        accessory="trash"
        tone="destructive"
        onclick={() => {
          if (
            window.confirm(
              "Delete this knowledge? Your agent will no longer recall this knowledge.",
            )
          )
            deleted = true;
        }}
      />
    </ContentGroup>
  {/if}
</SecondaryScreen>
