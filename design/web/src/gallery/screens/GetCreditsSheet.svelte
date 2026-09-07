<script lang="ts">
  import { ContentGroup, Icon, Row, Sheet } from "@lib";

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
      <!-- One card of rows, as the relay sheet uses: three prices are a list
           to compare, not three separate offers. -->
      <ContentGroup>
        {#each packs as pack (pack.credits)}
          <Row title="{pack.credits} credits" onclick={() => {}}>
            {#snippet trailing()}
              <span class="t-buttonSmall price">{pack.price}</span>
            {/snippet}
          </Row>
        {/each}
      </ContentGroup>

      <button class="restore" type="button">
        <Icon name="functional/refresh" size={14} />
        <span class="t-note">Restore credits</span>
      </button>

      <!-- Matches the iOS disclosure: footnote tone, the privacy link on its
           own line, and the whole thing quieter than body text. -->
      <p class="t-note disclosure">
        Payments are handled by the App Store. Conversations you send are processed by third-party
        AI providers in the EU on Eigin's behalf.
        <a class="policy" href="https://www.eigin.ai/privacy/">See the privacy policy.</a>
      </p>
    </div>
  {/snippet}
</Sheet>

<style>
  .packs {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n12);
    /* Cards run to the page inset, as they do on a settings screen: the
       card is the wide thing and its own padding holds the content to the
       grid. The header above keeps the sheet's deeper text inset. */
    padding: 0 var(--spacing-n16);
  }

  /* One column of prices rather than three pills of different widths. The
     minimum is on the content box, not the border box: with `border-box` the
     padding ate into it, so a long price still outgrew a short one. */
  .price {
    min-width: 6.5ch;
    text-align: center;
    font-variant-numeric: tabular-nums;
    padding: var(--spacing-n12) var(--spacing-n20);
    border-radius: var(--radius-full);
    background: var(--color-button-spot-base);
    color: var(--color-text-button-onSpot);
  }

  /* Lifted off the packs so it reads as its own secondary action, and inset
     by a pack's own padding so it starts on the same column the pack labels
     do rather than at the card's edge. */
  .restore {
    display: flex;
    align-items: center;
    gap: var(--spacing-n4);
    margin: var(--spacing-n16) var(--spacing-n24) 0;
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-text-standard-muted);
    font-family: inherit;
    cursor: pointer;
  }

  /* Sits close under restore: the two are the sheet's tail, and only the
     restore action needs lifting off the packs. */
  .disclosure {
    margin: 0 var(--spacing-n24);
    color: var(--color-text-standard-disabled);
  }

  .policy {
    display: block;
    margin-top: var(--spacing-n8);
    color: var(--color-text-standard-link);
  }
</style>
