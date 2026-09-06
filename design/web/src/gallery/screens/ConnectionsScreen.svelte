<script lang="ts">
  import { ActionButton, Button, ContentGroup, Icon, NavigationHeader, Row } from "@lib";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
</script>

<!--
  Settings → Connections: what Eigin thinks with, what it can reach, and what
  tools it has been given. Three groups, each ending in the way to add another.
-->
<div class="connections">
  <NavigationHeader title="Connections">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>

  <ScreenScroll>
    <ContentGroup label="Providers">
      <Row title="Eigin" description="Private cloud AI" onclick={() => {}} />
      <Row title="Anthropic" description="7 models available" onclick={() => {}} />
      <Row title="Mistral" description="4 models available" onclick={() => {}} />
      <Row title="Local model" description="Downloaded" onclick={() => {}} />
      <!-- The add action is the last row of the card, in the accent. -->
      <button class="add" type="button">
        <span class="t-titleXS">Add Provider</span>
        <Icon name="functional/plus" size={16} />
      </button>
    </ContentGroup>

    <ContentGroup label="Email">
      <Row title="Google" description="you@example.com" onclick={() => {}} />
      <Row title="Other email (IMAP)" description="you@icloud.com" onclick={() => {}} />
    </ContentGroup>

    <Button label="Add Integration" variant="secondary" size="medium" onclick={() => {}}>
      {#snippet trailing()}
        <Icon name="functional/plus" size={16} />
      {/snippet}
    </Button>

    <ContentGroup label="MCP Servers">
      <Row title="Home Assistant" description="12 tools" onclick={() => {}} />
      <Row title="Linear" description="https://mcp.linear.app/sse" onclick={() => {}} />
      <button class="add" type="button">
        <span class="t-titleXS">Add MCP Server</span>
        <Icon name="functional/plus" size={16} />
      </button>
    </ContentGroup>
  </ScreenScroll>
</div>

<style>
  .connections {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  /* Same metrics as a Row, but the whole line is the accent and the trailing
     mark is a plus rather than a chevron: this adds, it does not navigate. */
  .add {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--spacing-n16);
    width: 100%;
    box-sizing: border-box;
    padding: var(--spacing-n16) var(--spacing-n24);
    border: none;
    background: transparent;
    color: var(--color-accent);
    font-family: inherit;
    text-align: left;
    cursor: pointer;
  }
</style>
