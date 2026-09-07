<script lang="ts">
  import {
    ActionButton,
    BrandAvatar,
    Button,
    ContentGroup,
    Icon,
    IdentityHeader,
    NavigationHeader,
    Notice,
    Row,
  } from "@lib";
  import type { ConnectionState } from "@lib";
  import { untrack } from "svelte";
  import GetCreditsSheet from "@gallery/screens/GetCreditsSheet.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import RelayInfoSheet from "@gallery/screens/RelayInfoSheet.svelte";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  /** Opens a sheet with the screen; used by each sheet's own entry. */
  const { creditsOpen = false, infoOpen = false }: { creditsOpen?: boolean; infoOpen?: boolean } =
    $props();

  /* The prop seeds the initial state; the sheet owns it from there. */
  let showCredits = $state(untrack(() => creditsOpen));
  let showInfo = $state(untrack(() => infoOpen));

  const kinds = ["in credit", "running low", "empty", "unavailable"] as const;
  let kind = $state<(typeof kinds)[number]>("in credit");

  useStageControls(() => balance);

  const totals = { "in credit": "480", "running low": "84", empty: "0", unavailable: "480" };

  /* Empty is yours to fix and the button below fixes it; an outage is ours,
     and there is nothing on the screen you could press to end it. */
  const status = $derived.by<{ state: ConnectionState; label: string }>(() => {
    switch (kind) {
      case "empty":
        return { state: "attention", label: "Out of credits" };
      case "unavailable":
        return { state: "unavailable", label: "Unavailable" };
      default:
        return { state: "connected", label: "Ready to use" };
    }
  });
</script>

<!-- The balance is read from the account; here it is driven by hand. -->
{#snippet balance()}
  <OptionSelector options={kinds} bind:value={kind} />
{/snippet}

<!--
  Eigin as a provider: the same anatomy, order and metrics as every other
  provider screen, with our mark and our colour as the only difference.

  The balance sits in the facts rather than above them. An empty account is
  the one state that stops Eigin working, so the header says so and the button
  below answers it — the notice never carries its own action.
-->
<div class="eigin">
  <NavigationHeader title="Eigin Relay">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>

  <ScreenScroll>
    <IdentityHeader
      name="Eigin Relay"
      kind="Private cloud AI"
      state={status.state}
      status={status.label}
    >
      {#snippet mark()}
        <BrandAvatar size={64} inset={10}>
          <Icon name="brand/avatar" size="fill" />
        </BrandAvatar>
      {/snippet}
    </IdentityHeader>

    {#if kind === "unavailable"}
      <Notice
        tone="error"
        title="Eigin Relay is unavailable"
        body="The service is down, or you have lost connection. Chats using Eigin Relay will work once it is back."
      />
    {:else if kind === "empty"}
      <Notice
        onclick={() => (showCredits = true)}
        tone="warning"
        title="Eigin Relay is paused"
        body="Chats using Eigin Relay will not send until the account has credits again. Your other providers still work."
      />
    {:else if kind === "running low"}
      <Notice
        tone="info"
        title="Running low"
        body="You are close to running out. Top up now to avoid an interrupted chat."
      />
    {/if}

    <!-- The balance is the first fact, not a headline. It belongs with the
         other things worth knowing about the account, and reads the same way
         a model count does on any other provider. -->
    <ContentGroup footnote="One credit is about one eurocent of AI usage.">
      <Row title="Chat credits" value={totals[kind]} accessory="none" />
      <Row title="Hosted in" value="Europe" accessory="none" />
      <Row title="Conversations stored" value="Never" accessory="none" />
      <!-- Muted, like any row that defers to somewhere else: the card above
           already said what you needed, and this is the longer version. -->
      <Row title="How it works" onclick={() => (showInfo = true)} tone="muted" />
    </ContentGroup>

    <!-- No remove row: Eigin is the account, not a connection you added. -->
    <div class="bottom">
      <Button label="Get more credits" variant="spot" onclick={() => (showCredits = true)} />
    </div>
  </ScreenScroll>

  <GetCreditsSheet bind:open={showCredits} />
  <RelayInfoSheet bind:open={showInfo} />
</div>

<style>
  .eigin {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }
</style>
