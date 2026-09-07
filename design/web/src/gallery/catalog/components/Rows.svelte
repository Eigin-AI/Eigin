<script lang="ts">
  import { ContentGroup, Row, Switch } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let icon = $state("no icon");
  let supporting = $state("value");
  let accessory = $state("chevron");
  let tone = $state("standard");

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
    <OptionSelector options={["chevron", "link", "plus", "trash", "none"]} bind:value={accessory} />
    <OptionSelector options={["standard", "accent", "muted", "destructive"]} bind:value={tone} />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ContentGroup>
        <Row
          title="Soul"
          icon={icon === "icon" ? "functional/note" : undefined}
          value={supporting === "value" ? "You are a careful, plain-spoken…" : undefined}
          description={supporting === "description" ? "How the agent carries itself" : undefined}
          accessory={accessory as "chevron" | "link" | "plus" | "trash" | "none"}
          tone={tone as "standard" | "accent" | "muted" | "destructive"}
          onclick={() => {}}
        />
      </ContentGroup>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Content group</h2>
  <p class="lede t-description">
    Rows gather into a card, divided by hairlines inset to the text. The label is optional — the
    first group here has none. Small print belongs to the group rather than the page, so it is a
    prop: laid out by hand it drifts to the page gap, five times wider, and then reads as a
    statement about the whole screen.
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

        <ContentGroup label="About" footnote="Version numbers change with every release.">
          <Row title="Version" value="0.3.1" accessory="none" />
          <Row title="Open source licences" onclick={() => {}} />
          <Row title="Privacy policy" accessory="link" onclick={() => {}} />
        </ContentGroup>
      </div>
    </DeviceFrame>
  </div>
  <h2 class="t-titleM">Rows that act</h2>
  <p class="lede t-description">
    Adding, deferring and removing are the same row in another tone, not components of their own.
    Adding takes the accent and a plus: it is the one thing in a list of settled rows you might be
    hunting for, so it is allowed to be what the eye lands on. Muted defers — the rest of a list
    that was cut short, or the longer version of a fact — and what it opens is optional, because the
    card above already said what you needed. Destructive keeps its red to the glyph and never the
    label:
    <code>text.standard.error</code> is a pure signal red, and at title weight on a warm page it is the
    only cold, fully saturated thing on screen.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="page">
        <ContentGroup label="AI providers">
          <Row title="Anthropic" description="7 models" onclick={() => {}} />
          <Row title="Show all 11 models" onclick={() => {}} tone="muted" />
          <Row title="Add provider" onclick={() => {}} accessory="plus" tone="accent" />
        </ContentGroup>
        <ContentGroup>
          <Row title="Remove Anthropic" onclick={() => {}} accessory="trash" tone="destructive" />
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
