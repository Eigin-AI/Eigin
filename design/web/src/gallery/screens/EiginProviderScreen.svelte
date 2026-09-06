<script lang="ts">
  import { ActionButton, Button, Card, Icon, NavigationHeader, SubtleActionButton } from "@lib";
  import { untrack } from "svelte";
  import GetCreditsSheet from "@gallery/screens/GetCreditsSheet.svelte";
  import RelayInfoSheet from "@gallery/screens/RelayInfoSheet.svelte";

  /** Opens a sheet with the screen; used by each sheet's own entry. */
  const { creditsOpen = false, infoOpen = false }: { creditsOpen?: boolean; infoOpen?: boolean } =
    $props();

  /* The prop seeds the initial state; the sheet owns it from there. */
  let showCredits = $state(untrack(() => creditsOpen));
  let showInfo = $state(untrack(() => infoOpen));
</script>

<!--
  The Eigin credits home, reached from the permanent Eigin row in Connections:
  the balance, a way to buy more, and plain language about how the relay keeps
  inference private.
-->
<div class="eigin">
  <NavigationHeader title="Eigin">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>
  <div class="body">
    <div class="balance">
      <span class="t-display total">480</span>
      <div class="caption">
        <span class="t-titleXS">Chat Credits</span>
        <button class="refresh" type="button" aria-label="Refresh balance">
          <Icon name="functional/refresh" size={15} />
        </button>
      </div>
    </div>

    <div class="bottom">
      <!-- The compact card is headline/explainer only: no image. -->
      <Card
        size="compact"
        width="fill"
        headline="Private cloud AI"
        explainer="The easy, private way to use cloud AI. Nothing you say is stored, and we work only with trusted European providers."
      />
      <Button label="Get more credits" variant="spot" onclick={() => (showCredits = true)} />
      <SubtleActionButton label="Learn how it works" onclick={() => (showInfo = true)}>
        {#snippet icon()}
          <!-- The set has one chevron; pointing it is a rotation. -->
          <span class="chevron-right"><Icon name="functional/chevron/down" size={24} /></span>
        {/snippet}
      </SubtleActionButton>
    </div>
  </div>

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

  /* The balance floats in the middle, the pitch and its actions anchor low. */
  .body {
    display: flex;
    flex: 1;
    min-height: 0;
    flex-direction: column;
    justify-content: space-between;
    gap: var(--spacing-n40);
    padding: var(--spacing-n40) var(--spacing-n24) var(--spacing-n32);
  }

  .balance {
    display: flex;
    flex: 1;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-n8);
  }

  /* A changing balance must not shuffle its own digits. */
  .total {
    color: var(--color-text-standard-base);
    font-variant-numeric: tabular-nums;
  }

  .caption {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    color: var(--color-text-standard-muted);
  }

  /* Fixed size, so swapping the glyph for a spinner never shifts the caption. */
  .refresh {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-text-standard-muted);
    cursor: pointer;
  }

  .chevron-right {
    display: inline-flex;
    transform: rotate(-90deg);
  }

  .bottom {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }
</style>
