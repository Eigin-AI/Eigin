<script lang="ts">
  import { ActionButton, ContentGroup, NavigationHeader, Row, StatusLine } from "@lib";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
</script>

<!--
  The connections hub: two questions, not four mechanisms.

  Providers are where the thinking happens; integrations are everything Eigin
  can reach on your behalf. Whether an integration is built in, an MCP server
  or another agent is a fact on its own screen, not a group in this list, so
  there is one place to look and one way to add.
-->
<div class="connections">
  <NavigationHeader title="Connections">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>

  <ScreenScroll>
    <!-- Descriptions say what a connection gives you. Only one that needs
         something from you carries a status. -->
    <ContentGroup label="AI providers">
      <Row title="Eigin Relay" description="Private cloud AI" onclick={() => {}} />
      <Row title="Anthropic" description="7 models" onclick={() => {}} />
      <Row title="Local model" description="On this phone" onclick={() => {}} />
      <Row title="Add provider" onclick={() => {}} accessory="plus" tone="accent" />
    </ContentGroup>

    <ContentGroup label="Integrations">
      <Row title="Google" description="Mail, calendar and contacts" onclick={() => {}}>
        {#snippet trailing()}
          <StatusLine state="attention" label="Reconnect" />
        {/snippet}
      </Row>
      <Row title="iCloud mail" description="you@icloud.com" onclick={() => {}} />
      <Row title="Home Assistant" description="Lights, heating and sensors" onclick={() => {}} />
      <Row title="Linear" description="Issues and projects" onclick={() => {}} />
      <Row title="Reeva" description="Plans and books travel" onclick={() => {}} />
      <Row title="Add integration" onclick={() => {}} accessory="plus" tone="accent" />
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
</style>
