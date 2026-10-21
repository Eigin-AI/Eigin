<script lang="ts">
  import {
    ActionButton,
    AssetRow,
    Button,
    ContentGroup,
    IdentityHeader,
    NavigationHeader,
    Row,
  } from "@lib";
  import type { AssetState, ConnectionState } from "@lib";
  import LocalModelInfoSheet from "@gallery/screens/LocalModelInfoSheet.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { untrack } from "svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  /** Opens the sheet with the screen; used by the sheet's own entry. */
  const { infoOpen = false }: { infoOpen?: boolean } = $props();
  let showInfo = $state(untrack(() => infoOpen));

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
      reason: "This device doesn't have the hardware required to run the model.",
    },
  };

  /* The header says whether you can use it; the asset row below says what the
     download is doing. Neither repeats the other. */
  const status = $derived.by<{ state: ConnectionState; label: string }>(() => {
    switch (kind) {
      case "ready":
        return { state: "connected", label: "Ready to use" };
      case "downloading":
      case "preparing":
        return { state: "attention", label: "Getting ready" };
      case "unavailable":
        return { state: "unavailable", label: "Not supported" };
      default:
        return { state: "off", label: "Not installed" };
    }
  });

  /* One button carries the whole decision: get it, or stop getting it. */
  const action = $derived.by(() => {
    switch (kind) {
      case "not installed":
        return { label: "Download", variant: "primary" as const };
      case "downloading":
      case "preparing":
        return { label: "Cancel", variant: "secondary" as const };
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
  The model on the phone, on the same anatomy as every other provider: who it
  is, the facts, then the one thing to do about it.

  It is the one provider you have to fetch before you can use it, so the asset
  row sits where another screen lists its models, with the download directly
  under the thing being downloaded.
-->
<div class="local">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader title="Local model">
        {#snippet leading()}
          <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
        {/snippet}
      </NavigationHeader>
    {/snippet}

    <IdentityHeader
      name="Local model"
      kind="On this phone"
      icon="functional/lock"
      state={status.state}
      status={status.label}
    />

    <ContentGroup>
      <Row title="Good for" value="Quick chats, web search" accessory="none" />
      <Row title="Limitations" value="Complex tasks, tool use" accessory="none" />
      <Row title="How it works" tone="muted" onclick={() => (showInfo = true)} />
    </ContentGroup>

    <!-- The row carries the live state and its own size, so the screen says
         neither: its button is the only place the decision lives. -->
    <AssetRow
      name="Gemma 4 E2B"
      state={states[kind]}
      sizeDescription="~2.6 GB"
      showsAction={false}
    />

    {#if action}
      <Button label={action.label} variant={action.variant} onclick={() => {}} />
    {/if}

    {#if kind === "ready"}
      <ContentGroup>
        <Row title="Delete model" accessory="trash" tone="destructive" onclick={() => {}} />
      </ContentGroup>
    {/if}
  </ScreenScroll>

  <LocalModelInfoSheet bind:open={showInfo} />
</div>

<style>
  .local {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }
</style>
