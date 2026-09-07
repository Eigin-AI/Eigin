<script lang="ts">
  import { ActionButton, ContentGroup, NavigationHeader, Row, SearchField, Switch } from "@lib";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";

  let query = $state("");

  /* Ranked by the catalogue rather than by the provider's own order, then cut
     at five: the best things you can run here, and all of them arrive on. */
  let recommended = $state(
    [
      "Claude Opus 4.6",
      "Claude Sonnet 4.6",
      "Claude Haiku 4.5",
      "Claude Opus 4.1",
      "Claude Sonnet 4.5",
    ].map((name) => ({ name, on: true })),
  );

  /* Known too, just further down the ranking. Everything here works; it is
     simply not what we would reach for. */
  let other = $state(
    ["Claude Haiku 4", "Claude Opus 4", "Claude Sonnet 4", "Claude Sonnet 3.7"].map((name) => ({
      name,
      on: false,
    })),
  );

  /* IDs the catalogue has never seen. They may work; we cannot say how, so
     they start off and the person decides. */
  let unknown = $state(
    [
      "claude-3-5-sonnet-20240620",
      "claude-instant-1.2",
      "claude-2.1",
      "anthropic.internal-eval-3",
    ].map((name) => ({ name, on: false })),
  );

  const matches = (name: string) => name.toLowerCase().includes(query.trim().toLowerCase());
  const shownRecommended = $derived(recommended.filter((model) => matches(model.name)));
  const shownOther = $derived(other.filter((model) => matches(model.name)));
  const shownUnknown = $derived(unknown.filter((model) => matches(model.name)));
  const nothingShown = $derived(
    shownRecommended.length + shownOther.length + shownUnknown.length === 0,
  );
</script>

<!--
  Every model a provider offers, with a switch each.

  Three groups, by how much we can vouch for what is in them. Recommended is
  the top of the catalogue ranking, and all of it arrives on: a provider you
  just connected should be useful before you touch anything here. Other is the
  rest of what we recognise: it all works, it is simply not what we would
  reach for. Unknown is whatever else the provider's API listed: IDs the
  catalogue has never seen, which may work, so they start off and say why.

  This is the one list allowed to run to its end, and a list that long is only
  usable searched, which is why the field sits above it.
-->
<div class="models">
  <NavigationHeader title="Models">
    {#snippet leading()}
      <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
    {/snippet}
  </NavigationHeader>

  <ScreenScroll>
    <SearchField bind:value={query} placeholder="Search 47 models" />

    {#if nothingShown}
      <p class="t-note empty">No model matches “{query}”.</p>
    {/if}

    {#if shownRecommended.length > 0}
      <ContentGroup label="Recommended">
        {#each shownRecommended as model (model.name)}
          <Row title={model.name}>
            {#snippet trailing()}
              <Switch isOn={model.on} label={model.name} onclick={() => (model.on = !model.on)} />
            {/snippet}
          </Row>
        {/each}
      </ContentGroup>
    {/if}

    {#if shownOther.length > 0}
      <ContentGroup label="Other">
        {#each shownOther as model (model.name)}
          <Row title={model.name}>
            {#snippet trailing()}
              <Switch isOn={model.on} label={model.name} onclick={() => (model.on = !model.on)} />
            {/snippet}
          </Row>
        {/each}
      </ContentGroup>
    {/if}

    {#if shownUnknown.length > 0}
      <ContentGroup
        label="Unknown"
        footnote="Models we don't recognise. They may work, they may not. Turning one on is your call."
      >
        {#each shownUnknown as model (model.name)}
          <Row title={model.name}>
            {#snippet trailing()}
              <Switch isOn={model.on} label={model.name} onclick={() => (model.on = !model.on)} />
            {/snippet}
          </Row>
        {/each}
      </ContentGroup>
    {/if}
  </ScreenScroll>
</div>

<style>
  .models {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .empty {
    margin: 0;
    padding: 0 var(--spacing-n8);
    color: var(--color-text-standard-muted);
  }
</style>
