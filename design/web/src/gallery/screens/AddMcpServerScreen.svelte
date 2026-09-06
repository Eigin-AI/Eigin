<script lang="ts">
  import {
    ActionButton,
    CardSurface,
    ContentGroup,
    Icon,
    NavigationHeader,
    Row,
    TextInput,
  } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  /* The form auto-detects whether a server is open or wants OAuth, so the
     screen moves through phases rather than pages. */
  const phases = ["idle", "checking", "credentials", "error", "done"] as const;
  let phase = $state<(typeof phases)[number]>("idle");

  useStageControls(() => phaseControl);

  let name = $state("Linear");
  let url = $state("https://mcp.linear.app/sse");
  let clientID = $state("");
  let clientSecret = $state("");

  const tools = ["Create Issue", "List Issues", "Update Issue"];

  /* The trailing action is whatever the phase can do next. */
  const nextIcon = $derived.by(() => {
    if (phase === "checking") return undefined;
    return phase === "done" ? ("functional/plus" as const) : ("functional/arrow/right" as const);
  });
</script>

<!-- The app detects the phase from the server; here it is driven by hand. -->
{#snippet phaseControl()}
  <OptionSelector options={phases} bind:value={phase} />
{/snippet}

<!--
  Adding an MCP server: name it, point at it, and let the probe work out
  whether it is open or wants authorising. Tools appear once it answers.

  Presented as a page over Connections — the modal-page presentation, so the
  card takes the room and the form brings its own navigation header rather
  than a sheet header.
-->
<div class="add-mcp">
  <NavigationHeader title="Add MCP Server">
    {#snippet leading()}
      <ActionButton icon="functional/x" variant="open" size="medium" label="Close" />
    {/snippet}
    {#snippet trailing()}
      {#if nextIcon}
        <ActionButton icon={nextIcon} variant="open" size="medium" label="Continue" />
      {/if}
    {/snippet}
  </NavigationHeader>

  <ScreenScroll>
    <div class="fields">
      <TextInput label="Name" bind:value={name} />
      <TextInput label="Server URL" bind:value={url} />
      <p class="t-tag hint">
        <Icon name="functional/info" size={14} />
        The server must support the Model Context Protocol (MCP) over Streamable HTTP.
      </p>
    </div>

    {#if phase === "checking"}
      <CardSurface>
        <p class="t-tag muted">Checking server...</p>
      </CardSurface>
    {:else if phase === "credentials"}
      <ContentGroup label="Client Credentials">
        <div class="credentials">
          <TextInput label="Client ID" bind:value={clientID} />
          <TextInput label="Client Secret" bind:value={clientSecret} isSecure />
        </div>
      </ContentGroup>
      <p class="t-tag hint">
        This server doesn't support automatic registration. Enter the client credentials from your
        OAuth provider.
      </p>
    {:else if phase === "error"}
      <CardSurface>
        <div class="error">
          <p class="t-titleXS bad">
            <Icon name="functional/warning" size={16} />
            Connection failed
          </p>
          <p class="t-tag muted">The server did not answer the probe.</p>
        </div>
      </CardSurface>
    {/if}

    {#if phase === "done"}
      <ContentGroup label="Tools">
        {#each tools as tool (tool)}
          <Row title={tool} accessory="none" />
        {/each}
      </ContentGroup>
    {/if}
  </ScreenScroll>
</div>

<style>
  .add-mcp {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .fields,
  .credentials {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
  }

  .credentials {
    padding: var(--spacing-n16) var(--spacing-n24);
  }

  p {
    margin: 0;
  }

  .hint {
    display: flex;
    align-items: flex-start;
    gap: var(--spacing-n8);
    padding: 0 var(--spacing-n8);
    color: var(--color-text-standard-muted);
  }

  .muted {
    color: var(--color-text-standard-muted);
  }

  .error {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n8);
  }

  .bad {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    color: var(--color-text-standard-error);
  }
</style>
