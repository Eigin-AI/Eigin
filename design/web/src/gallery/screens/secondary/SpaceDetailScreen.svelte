<script lang="ts">
  import { ActionButton, ContentGroup, NavigationHeader, Row, Switch } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import { EmptyState } from "@lib";
  let name = $state("Travel");
  let emoji = $state("🚆");
  let editingName = $state(false);
  let instructions = $state(
    "Prefer trains over flights when practical. Look for small hotels and vegetarian places to eat.",
  );
  let editingInstructions = $state(false);
  let isPrivate = $state(false);
  let deleted = $state(false);
</script>

{#if editingInstructions}
  <div class="editor-screen">
    <NavigationHeader title="Instructions">
      {#snippet leading()}
        <ActionButton
          icon="functional/arrow/left"
          variant="open"
          size="medium"
          label="Back"
          onclick={() => (editingInstructions = false)}
        />
      {/snippet}
    </NavigationHeader>
    <textarea
      class="editor t-chatMessageUser"
      aria-label="Space instructions"
      bind:value={instructions}
    ></textarea>
  </div>
{:else}
  <SecondaryScreen title="Space" back="spaces">
    {#if deleted}<EmptyState
        icon="functional/check_circle"
        title="Space deleted"
        description="This space has been removed from the preview."
        action="Restore preview"
        onclick={() => (deleted = false)}
      />
    {:else}
      <ContentGroup label="Identity">
        <div class="identity">
          <button
            class="emoji"
            type="button"
            aria-label="Change symbol"
            onclick={() => (emoji = emoji === "🚆" ? "🌍" : "🚆")}>{emoji}</button
          >
          {#if editingName}
            <!-- svelte-ignore a11y_autofocus -->
            <input
              class="t-titleM name-field"
              aria-label="Space name"
              bind:value={name}
              autofocus
              onblur={() => (editingName = false)}
              onkeydown={(event) => {
                if (event.key === "Enter") editingName = false;
              }}
            />
          {:else}
            <button class="t-titleM name" type="button" onclick={() => (editingName = true)}>
              {name}
            </button>
          {/if}
        </div>
        <Row title="Instructions" onclick={() => (editingInstructions = true)} />
      </ContentGroup>
      <ContentGroup footnote="Data created here stays hidden from other spaces.">
        <Row title="Private space" accessory="none">
          {#snippet trailing()}<Switch
              label="Private space"
              isOn={isPrivate}
              onclick={() => (isPrivate = !isPrivate)}
            />{/snippet}
        </Row>
      </ContentGroup>
      <ContentGroup>
        <Row
          title="Delete space"
          accessory="trash"
          tone="destructive"
          onclick={() => {
            if (window.confirm("Delete this space? Its chats will be kept outside the space."))
              deleted = true;
          }}
        />
      </ContentGroup>
    {/if}
  </SecondaryScreen>
{/if}

<style>
  .identity {
    display: flex;
    align-items: center;
    gap: var(--spacing-n12);
    padding: var(--spacing-n16) var(--spacing-n24);
  }
  .emoji {
    font-size: 40px;
    line-height: 1;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
  }
  .name,
  .name-field {
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-standard-base);
    text-align: left;
  }
  .name {
    cursor: text;
  }
  .name:focus-visible {
    outline: 2px solid var(--color-icon-standard-base);
    outline-offset: 4px;
    border-radius: var(--radius-card);
  }
  .name-field:focus {
    outline: none;
  }
  /* Full-screen text editing, edge to edge below the header. */
  .editor-screen {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    background: var(--color-surface-standard-base);
  }
  .editor {
    box-sizing: border-box;
    width: 100%;
    flex: 1;
    min-height: 0;
    padding: var(--spacing-n16) var(--spacing-n24);
    border: none;
    background: none;
    color: var(--color-text-standard-base);
    resize: none;
  }
  .editor:focus {
    outline: none;
  }
</style>
