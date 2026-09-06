<script lang="ts">
  import { Icon, Sheet } from "@lib";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* Each row buys a pack; the relay grants the credits and stores the wallet. */
  const packs = [
    { credits: "500", price: "€5.99" },
    { credits: "1 200", price: "€12.99" },
    { credits: "3 000", price: "€29.99" },
  ];
</script>

<!--
  Purchase options for Eigin credits. The pricing note lives in the sheet's
  description, and restore sits under the packs as its own quieter action.
-->
<Sheet
  bind:open
  title="Get more credits"
  description="Credits let you use private cloud AI through the Eigin Relay."
>
  {#snippet primary()}
    <div class="packs">
      {#each packs as pack (pack.credits)}
        <button class="pack" type="button">
          <span class="t-titleXS">{pack.credits} credits</span>
          <span class="t-buttonSmall price">{pack.price}</span>
        </button>
      {/each}

      <button class="restore" type="button">
        <Icon name="functional/refresh" size={14} />
        <span class="t-note">Restore credits</span>
      </button>

      <p class="t-note disclosure">
        Payments are handled by the App Store. Eigin Relay routes your requests to third-party AI
        providers in Europe.
      </p>
    </div>
  {/snippet}
</Sheet>

<style>
  .packs {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n12);
    padding: 0 var(--sizing-pageLayout-headerGrouping-px-mobile);
  }

  .pack {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--spacing-n16);
    box-sizing: border-box;
    width: 100%;
    padding: var(--spacing-n20) var(--spacing-n24);
    border: none;
    border-radius: var(--radius-card);
    background: var(--color-button-standard-secondary);
    color: var(--color-text-standard-base);
    font-family: inherit;
    text-align: left;
    cursor: pointer;
  }

  .price {
    padding: var(--spacing-n12) var(--spacing-n20);
    border-radius: var(--radius-full);
    background: var(--color-button-spot-base);
    color: var(--color-text-button-onSpot);
  }

  /* Lifted off the packs so it reads as its own secondary action. */
  .restore {
    display: flex;
    align-items: center;
    gap: var(--spacing-n4);
    margin-top: var(--spacing-n16);
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-text-standard-muted);
    font-family: inherit;
    cursor: pointer;
  }

  .disclosure {
    margin: 0;
    color: var(--color-text-standard-muted);
  }
</style>
