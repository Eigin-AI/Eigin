<script lang="ts">
  import { ActionButton, AssetRow, Button, ContentGroup, NavigationHeader, Row } from "@lib";
  import type { AssetState } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  const kinds = ["not installed", "downloading", "preparing", "ready", "unavailable"] as const;
  let kind = $state<(typeof kinds)[number]>("ready");

  useStageControls(() => modelState);

  const states: Record<(typeof kinds)[number], AssetState> = {
    "not installed": { kind: "notDownloaded" },
    downloading: { kind: "downloading", fractionCompleted: 0.62, estimatedSecondsLeft: 42 },
    preparing: { kind: "preparing" },
    ready: { kind: "ready" },
    unavailable: {
      kind: "unavailable",
      reason:
        "This device doesn't have enough memory to run the local model. iPhone 15 or later is required.",
    },
  };

  /* One button carries the whole decision: get it, stop it, or remove it. */
  const action = $derived.by(() => {
    switch (kind) {
      case "not installed":
        return { label: "Download", variant: "primary" as const };
      case "downloading":
        return { label: "Cancel", variant: "secondary" as const };
      case "ready":
        return { label: "Delete", variant: "secondary" as const };
      default:
        return undefined;
    }
  });
</script>

<!-- The app reads this from the download itself; here it is driven by hand. -->
{#snippet modelState()}
  <OptionSelector options={kinds} bind:value={kind} />
{/snippet}

<!--
  The on-device model: what it is, what to expect of it, and the one decision
  worth making about it. The row carries the live status, so it drops its own
  control — the action is the button at the bottom.
-->
<div class="local">
  <NavigationHeader title="Local model">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>

  <div class="body">
    <div class="head">
      <AssetRow
        name="Gemma 4 E2B"
        state={states[kind]}
        sizeDescription="~2.6 GB"
        showsAction={false}
      />

      <!-- What you can't read off the title, the row, or the description. -->
      <ContentGroup>
        <Row title="Good for" value="Quick chats, web search" accessory="none" />
        <Row title="Limitations" value="Basic reasoning, few tools" accessory="none" />
        <Row title="Size on device" value="~2.6 GB" accessory="none" />
      </ContentGroup>

      <p class="t-description blurb">On-device assistant model</p>
    </div>

    {#if action}
      <Button label={action.label} variant={action.variant} onclick={() => {}} />
    {/if}
  </div>
</div>

<style>
  .local {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  /* Facts at the top, the decision anchored at the bottom. */
  .body {
    display: flex;
    flex: 1;
    min-height: 0;
    flex-direction: column;
    justify-content: space-between;
    gap: var(--spacing-n32);
    overflow-y: auto;
    padding: var(--spacing-n8) var(--spacing-n24) var(--spacing-n32);
  }

  .head {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
  }

  .blurb {
    margin: 0;
    color: var(--color-text-standard-muted);
  }
</style>
