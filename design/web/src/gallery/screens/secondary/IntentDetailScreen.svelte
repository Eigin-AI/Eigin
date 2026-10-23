<script lang="ts">
  import { ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import { EmptyState } from "@lib";
  import DetailText from "./DetailText.svelte";
  import { intents, type GalleryIntent } from "./intentsData";
  let { intent = intents[0], onBack }: { intent?: GalleryIntent; onBack?: () => void } = $props();
  let dismissed = $state(false);
</script>

<SecondaryScreen title="Intent" back="intents" {onBack}>
  {#if dismissed}
    <EmptyState
      icon="functional/check_circle"
      title="Intent dismissed"
      description="Your agent will stop following up on this goal."
      action="Restore preview"
      onclick={() => (dismissed = false)}
    />
  {:else}
    <ContentGroup label="Content"><DetailText text={intent.content} /></ContentGroup>
    {#if intent.tasks.length}
      <ContentGroup label="Tasks">
        {#each intent.tasks as task (task.content)}
          <Row
            title={task.content}
            description={task.due}
            icon={task.completed ? "functional/check" : undefined}
            accessory="none"
            tone={task.completed ? "muted" : "standard"}
          />
        {/each}
      </ContentGroup>
    {/if}
    {#if intent.events.length}
      <ContentGroup label="Events">
        {#each intent.events as event (event.content)}<Row
            title={event.content}
            description={event.at}
            accessory="none"
          />{/each}
      </ContentGroup>
    {/if}
    {#if intent.schedules.length}
      <ContentGroup label="Schedules">
        {#each intent.schedules as schedule (schedule.content)}<Row
            title={schedule.content}
            description={schedule.when}
            accessory="none"
          />{/each}
      </ContentGroup>
    {/if}
    <ContentGroup label="Details">
      <Row title="Created" value="19 October" accessory="none" />
      <Row title="Updated" value="20 minutes ago" accessory="none" />
    </ContentGroup>
    <ContentGroup>
      <Row
        title="Dismiss intent"
        accessory="trash"
        tone="destructive"
        onclick={() => {
          if (
            window.confirm("Dismiss this intent? Your agent will stop working towards this goal.")
          )
            dismissed = true;
        }}
      />
    </ContentGroup>
  {/if}
</SecondaryScreen>
