<script lang="ts">
  import {
    ActionButton,
    Button,
    CardSurface,
    ContentGroup,
    Icon,
    NavigationHeader,
    Row,
  } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  const conditions = ["healthy", "partly granted", "needs reconnect"] as const;
  let condition = $state<(typeof conditions)[number]>("healthy");

  useStageControls(() => conditionControl);

  /* A type can provide several capabilities; the account may have approved
     only some of them. */
  const capabilities = $derived([
    { name: "Email", granted: true },
    { name: "Calendar", granted: condition !== "partly granted" },
    { name: "Contacts", granted: condition !== "partly granted" },
  ]);
</script>

<!-- The app reads this from the connection; here it is driven by hand. -->
{#snippet conditionControl()}
  <OptionSelector options={conditions} bind:value={condition} />
{/snippet}

<!--
  One connected integration: which account it is, what it was allowed to do,
  and the two things you can do about it — reconnect, or disconnect.
-->
<div class="integration">
  <NavigationHeader title="you@example.com">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>

  <ScreenScroll>
    {#if condition === "needs reconnect"}
      <CardSurface>
        <div class="attention">
          <p class="t-titleXS bad">
            <Icon name="functional/warning" size={16} />
            Reconnect needed
          </p>
          <p class="t-tag muted">
            The connection can't sign in automatically anymore — its session or credentials expired.
            Reconnect to restore access.
          </p>
        </div>
      </CardSurface>
    {/if}

    <ContentGroup>
      <Row title="Name" value="Google" accessory="none" />
      <Row title="Account" value="you@example.com" accessory="none" />
    </ContentGroup>

    {#if condition === "partly granted"}
      <ContentGroup label="Integrations">
        {#each capabilities as entry (entry.name)}
          <Row title={entry.name} accessory="none" trailing={entry.granted ? granted : denied} />
        {/each}
      </ContentGroup>
      <p class="t-tag hint">
        Not granted — reconnect this integration to approve the permissions you skipped.
      </p>
    {/if}

    <Button label="Reconnect" variant="secondary" onclick={() => {}} />
    <Button label="Disconnect" variant="destructive" onclick={() => {}} />
  </ScreenScroll>
</div>

{#snippet granted()}
  <span class="mark on"><Icon name="functional/check_circle" size={20} /></span>
{/snippet}

{#snippet denied()}
  <span class="mark"><Icon name="functional/x" size={20} /></span>
{/snippet}

<style>
  .integration {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  p {
    margin: 0;
  }

  .attention {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n8);
  }

  .bad {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    color: var(--color-text-standard-error);
  }

  .muted,
  .hint {
    color: var(--color-text-standard-muted);
  }

  .hint {
    padding: 0 var(--spacing-n8);
  }

  .mark {
    display: inline-flex;
    color: var(--color-text-standard-muted);
  }

  .mark.on {
    color: var(--color-icon-signal-approve);
  }
</style>
