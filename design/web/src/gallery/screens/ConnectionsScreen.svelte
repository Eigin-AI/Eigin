<script lang="ts">
  import { ActionButton, ContentGroup, NavigationHeader, Row, StatusLine } from "@lib";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import { hardwareGuidance, unsupportedDescription } from "@gallery/screens/localModel";

  let hardware = $state("supported device");
  useStageControls(() => controls);
</script>

{#snippet controls()}
  <OptionSelector options={["supported device", "unsupported device"]} bind:value={hardware} />
{/snippet}

<!--
  The connections hub: two questions, not four mechanisms.

  Providers are where the thinking happens; integrations are everything Eigin
  can reach on your behalf. Whether an integration is built in, an MCP server
  or another agent is a fact on its own screen, not a group in this list, so
  there is one place to look and one way to add.
-->
<div class="connections">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader title="Connections">
        {#snippet leading()}
          <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
        {/snippet}
      </NavigationHeader>
    {/snippet}

    <!-- Descriptions say what a connection gives you. Only one that needs
         something from you carries a status. -->
    <ContentGroup label="AI providers">
      <Row title="Eigin Relay" description="Private cloud AI" onclick={() => {}} />
      <Row title="Anthropic" description="7 models" onclick={() => {}} />
      {#if hardware === "supported device"}
        <Row
          title="Local model"
          description="On this phone"
          onclick={() => (location.hash = "#/screens/local-model")}
        />
      {:else}
        <Row
          title="Local model"
          description={`${unsupportedDescription} ${hardwareGuidance}`}
          accessory="none"
        />
      {/if}
      <Row title="Add provider" onclick={() => {}} accessory="plus" tone="accent" />
    </ContentGroup>

    <ContentGroup label="Integrations">
      <Row title="Google" description="Mail, calendar and contacts" onclick={() => {}}>
        {#snippet trailing()}
          <StatusLine state="attention" label="Reconnect" />
        {/snippet}
      </Row>
      <Row
        title="Apple Health"
        description="Activity, sleep and nutrition"
        onclick={() => (location.hash = "#/screens/platform-integration")}
      />
      <Row title="Apple Calendar" description="Events on this phone" onclick={() => {}} />
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
