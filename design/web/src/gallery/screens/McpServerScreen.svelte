<script lang="ts">
  import {
    ActionButton,
    Button,
    ContentGroup,
    Disclosure,
    Icon,
    NavigationHeader,
    Row,
  } from "@lib";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  const states = ["connected", "idle", "error", "disabled"] as const;
  let status = $state<(typeof states)[number]>("connected");

  const label = $derived(
    status === "connected"
      ? "Connected"
      : status === "error"
        ? "Not connected"
        : status === "disabled"
          ? "Disabled"
          : "Not connected",
  );

  useStageControls(() => statusControl);

  const tools = [
    "Create Issue",
    "List Issues",
    "Update Issue",
    "Search Documents",
    "List Projects",
  ];
</script>

<!-- The app reads the status from the connection; here it is driven by hand. -->
{#snippet statusControl()}
  <OptionSelector options={states} bind:value={status} />
{/snippet}

<!--
  One MCP server: where it lives and how it authenticates, whether the
  connection is up, the tools it has offered, and the way to remove it.
-->
<div class="mcp">
  <NavigationHeader title="Linear">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>

  <ScreenScroll>
    <ContentGroup>
      <Row title="URL" value="https://mcp.linear.app/sse" accessory="none" />
      <Row title="Authentication" value="OAuth" accessory="none" />
    </ContentGroup>

    <Disclosure title="Status" description={label}>
      {#if status === "connected"}
        <p class="t-tag line">
          <span class="dot" aria-hidden="true"></span>
          Connection is active.
        </p>
      {:else if status === "idle"}
        <p class="t-tag muted">Connects automatically when used in a chat.</p>
      {:else if status === "disabled"}
        <p class="t-tag muted">This server is disabled and won't be used in chats.</p>
      {:else}
        <div class="error">
          <p class="t-tag bad">The server refused the connection: token expired.</p>
          <button class="reauth t-tag" type="button">
            <Icon name="functional/refresh" size={16} />
            Re-authorize
          </button>
        </div>
      {/if}
    </Disclosure>

    <ContentGroup label="Tools">
      {#each tools as tool (tool)}
        <Row title={tool} accessory="none" />
      {/each}
    </ContentGroup>

    <Button label="Remove" variant="destructive" onclick={() => {}} />
  </ScreenScroll>
</div>

<style>
  .mcp {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  p {
    margin: 0;
  }

  .line {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    color: var(--color-text-standard-muted);
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: var(--radius-full);
    background: var(--color-icon-signal-approve);
  }

  .muted {
    color: var(--color-text-standard-muted);
  }

  .bad {
    color: var(--color-text-standard-error);
  }

  .error {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n12);
    align-items: flex-start;
  }

  .reauth {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-n8);
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-accent);
    font-family: inherit;
    cursor: pointer;
  }
</style>
