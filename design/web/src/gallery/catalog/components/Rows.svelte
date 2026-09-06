<script lang="ts">
  import { Row, ContentGroup, Switch } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let icon = $state("no icon");
  let supporting = $state("value");
  let accessory = $state("chevron");

  let sync = $state(true);
  let analytics = $state(false);
</script>

<div class="doc">
  <h2 class="t-titleM">Row</h2>
  <p class="lede t-description">
    The line a settings screen is built from: an optional glyph, a title, a supporting line or a
    value, and an accessory saying what a tap does. Nothing to tap means text, not a button.
  </p>
  <div class="controls">
    <OptionSelector options={["no icon", "icon"]} bind:value={icon} />
    <OptionSelector options={["value", "description", "neither"]} bind:value={supporting} />
    <OptionSelector options={["chevron", "link", "none"]} bind:value={accessory} />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ContentGroup>
        <Row
          title="Soul"
          icon={icon === "icon" ? "functional/note" : undefined}
          value={supporting === "value" ? "You are a careful, plain-spoken…" : undefined}
          description={supporting === "description" ? "How the agent carries itself" : undefined}
          accessory={accessory as "chevron" | "link" | "none"}
          onclick={() => {}}
        />
      </ContentGroup>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Content group</h2>
  <p class="lede t-description">
    Rows gather into a card, divided by hairlines inset to the text. The label is optional — the
    first group here has none.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="page">
        <ContentGroup>
          <Row title="Identity" value="Eigin" onclick={() => {}} />
          <Row title="Soul" value="You are a careful, plain-spoken…" onclick={() => {}} />
          <Row title="Skills" onclick={() => {}} />
        </ContentGroup>

        <ContentGroup label="Privacy">
          <Row title="Sync over Wi-Fi only" description="Large uploads wait for a network">
            {#snippet trailing()}
              <Switch isOn={sync} label="Sync over Wi-Fi only" onclick={() => (sync = !sync)} />
            {/snippet}
          </Row>
          <Row title="Share diagnostics">
            {#snippet trailing()}
              <Switch
                isOn={analytics}
                label="Share diagnostics"
                onclick={() => (analytics = !analytics)}
              />
            {/snippet}
          </Row>
        </ContentGroup>

        <ContentGroup label="About">
          <Row title="Version" value="0.3.1" accessory="none" />
          <Row title="Open source licences" onclick={() => {}} />
          <Row title="Privacy policy" accessory="link" onclick={() => {}} />
        </ContentGroup>
      </div>
    </DeviceFrame>
  </div>
</div>

<style>
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
  }

  /* Sections stack with the page layout gap, as the settings screens do. */
  .page {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
  }
</style>
