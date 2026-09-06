<script lang="ts">
  import {
    Sheet,
    SheetHeader,
    SubtleActionButton,
    SelectorButton,
    Button,
    GridScope,
    Icon,
    SheetActions,
  } from "@lib";
  import type { SheetAction } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let showEpisode = $state(false);
  let showWizard = $state(false);
  let showConfirm = $state(false);
  let showLong = $state(false);
  let showActions = $state(false);

  const actions: SheetAction[] = [
    { label: "Spaces", icon: "functional/note", onclick: () => (showActions = false) },
    { label: "Attach photo", icon: "functional/attachment", onclick: () => (showActions = false) },
    { label: "Record audio", icon: "functional/microphone", onclick: () => (showActions = false) },
  ];

  let mood = $state<number | null>(null);

  let headerLabel = $state("no label");
  let headerDescription = $state("description");
  let headerDismiss = $state("close button");
</script>

<div class="doc">
  <h2 class="t-titleM">Header</h2>
  <p class="lede t-description">
    Every sheet opens with the same block: an optional label, the title, an optional description,
    and the dismiss button in the corner. Title alone centres against the button; with supporting
    text the whole block top-aligns.
  </p>
  <div class="controls">
    <OptionSelector options={["no label", "label"]} bind:value={headerLabel} />
    <OptionSelector options={["no description", "description"]} bind:value={headerDescription} />
    <OptionSelector options={["close button", "no close button"]} bind:value={headerDismiss} />
  </div>
  <div class="sheet-top">
    <GridScope>
      <div class="grabber"></div>
      <SheetHeader
        title="Headline goes here"
        label={headerLabel === "label" ? "Label text" : undefined}
        description={headerDescription === "description"
          ? "Explainer text goes right here"
          : undefined}
        onDismiss={headerDismiss === "close button" ? () => {} : undefined}
      />
    </GridScope>
  </div>

  <h2 class="t-titleM">Sheet</h2>
  <p class="lede t-description">
    A card over the screen, bottom-anchored, with the screen dimmed behind it. A sheet is as tall as
    what it holds and no taller than the room above it — it stops below the container's top safe
    area, and anything past that scrolls inside. Open one to try it: dismiss with the close button,
    the backdrop, or Escape.
  </p>
  <div class="phone stage-frame">
    <GridScope>
      <div class="stack">
        <SubtleActionButton label="Episode info" onclick={() => (showEpisode = true)}>
          {#snippet icon()}<Icon name="functional/edit" size={24} />{/snippet}
        </SubtleActionButton>
        <SubtleActionButton label="How did you sleep?" onclick={() => (showWizard = true)}>
          {#snippet icon()}<Icon name="functional/note" size={24} />{/snippet}
        </SubtleActionButton>
        <SubtleActionButton label="Delete recording" onclick={() => (showConfirm = true)}>
          {#snippet icon()}<Icon name="functional/trash" size={24} />{/snippet}
        </SubtleActionButton>
        <SubtleActionButton label="Preferences" onclick={() => (showLong = true)}>
          {#snippet icon()}<Icon name="functional/dots/horizontal" size={24} />{/snippet}
        </SubtleActionButton>
        <SubtleActionButton label="Add to chat" onclick={() => (showActions = true)}>
          {#snippet icon()}<Icon name="functional/plus" size={24} />{/snippet}
        </SubtleActionButton>
      </div>

      <!-- Label + title + description: the fullest header. -->
      <Sheet
        bind:open={showEpisode}
        label="Recording"
        title="Edit episode"
        description="Changes save to this episode only."
      >
        {#snippet primary()}
          <div class="group">
            <div class="info-card">
              <div class="info-row">
                <span class="info-label">Title</span><span class="info-value">Morning run</span>
              </div>
              <div class="info-row">
                <span class="info-label">Date</span><span class="info-value">15 May 2026</span>
              </div>
              <div class="info-row">
                <span class="info-label">Duration</span><span class="info-value">32 min</span>
              </div>
            </div>
            <SubtleActionButton label="Add a note" onclick={() => {}}>
              {#snippet icon()}<Icon name="functional/plus" size={24} />{/snippet}
            </SubtleActionButton>
            <Button label="Save changes" variant="secondary" onclick={() => {}} />
          </div>
        {/snippet}
      </Sheet>

      <!-- Title + description, no label. -->
      <Sheet
        bind:open={showWizard}
        title="How did you sleep?"
        description="One tap, then we will leave you alone."
      >
        {#snippet primary()}
          <div class="group">
            {#each ["Great", "Good", "OK", "Poor"] as mood_, index (mood_)}
              <SelectorButton
                label={mood_}
                isSelected={mood === index}
                onclick={() => (mood = index)}
              />
            {/each}
            <Button label="Continue" onclick={() => {}} disabled={mood === null} />
          </div>
        {/snippet}
      </Sheet>

      <!-- Description but no dismiss: the way out is one of the buttons. -->
      <Sheet
        bind:open={showConfirm}
        title="Delete recording"
        description="This cannot be undone."
        showsDismissButton={false}
      >
        {#snippet primary()}
          <div class="group">
            <Button label="Delete" variant="destructive" onclick={() => (showConfirm = false)} />
            <Button label="Cancel" variant="secondary" onclick={() => (showConfirm = false)} />
          </div>
        {/snippet}
        {#snippet secondary()}
          <div class="group">
            <SubtleActionButton label="Permanently delete" onclick={() => (showConfirm = false)}>
              {#snippet icon()}<Icon name="functional/trash" size={24} />{/snippet}
            </SubtleActionButton>
          </div>
        {/snippet}
      </Sheet>

      <!-- The action-list preset: a sheet whose content is a short list of actions. -->
      <Sheet bind:open={showActions} label="Chat" title="Add to chat">
        {#snippet primary()}
          <SheetActions {actions} />
        {/snippet}
      </Sheet>

      <Sheet bind:open={showLong} title="Preferences">
        {#snippet primary()}
          <div class="group">
            {#each ["Notifications", "Privacy", "Appearance", "Language", "Storage", "Integrations", "Advanced", "About"] as item (item)}
              <SubtleActionButton label={item} onclick={() => {}}>
                {#snippet icon()}<Icon name="functional/chevron/down" size={24} />{/snippet}
              </SubtleActionButton>
            {/each}
          </div>
        {/snippet}
      </Sheet>
    </GridScope>
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

  /* Each header shown on the top edge of a sheet, which is where it lives. */
  .sheet-top {
    width: 393px;
    margin-bottom: var(--spacing-n40);
    padding-bottom: var(--spacing-n32);
    background: var(--color-surface-standard-base);
    border-radius: var(--radius-card) var(--radius-card) 0 0;
    box-shadow: 0 -1px 0 var(--color-border-standard-base);
  }

  .grabber {
    width: 36px;
    height: 5px;
    margin: var(--spacing-n8) auto var(--spacing-n32);
    border-radius: 999px;
    background: color-mix(in srgb, var(--color-border-standard-base) 60%, transparent);
  }

  /* The mock screen the sheets present over. Anchors the sheet layer. */
  .phone {
    position: relative;
    width: 393px;
    background: var(--color-surface-standard-base);
    border-radius: var(--radius-card);
    outline: 1px dashed var(--color-border-standard-base);
    margin-bottom: var(--spacing-n40);
    overflow: hidden;
  }

  .stage-frame {
    height: 640px;
  }

  .stack {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: var(--spacing-n24);
    padding: var(--spacing-n24) 0;
  }

  /* Content grouping inside a sheet's primary block. */
  .group {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
    padding: 0 var(--sizing-pageLayout-contentGrouping-px-mobile);
  }

  .info-card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
    padding: var(--spacing-n24) var(--spacing-n16);
    background: var(--color-surface-standard-alternative);
    border-radius: var(--radius-card);
  }

  .info-row {
    display: flex;
    gap: var(--spacing-n16);
  }

  .info-label {
    width: 72px;
    color: var(--color-text-standard-base);
  }

  .info-value {
    color: var(--color-text-standard-muted);
  }
</style>
