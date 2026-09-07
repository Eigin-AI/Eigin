<script lang="ts">
  import { ContentGroup, Row, Sheet } from "@lib";
  import type { IconName } from "@lib";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* The pitch lives in the sheet's description; each point is an icon, a
     headline and a sentence or two. Three lines is the ceiling: past that a
     row stops being a fact and starts being a paragraph. */
  const points: { icon: IconName; title: string; body: string }[] = [
    {
      icon: "functional/lock",
      title: "Always private",
      body: "There is no account and conversations are never stored.",
    },
    {
      icon: "functional/globe",
      title: "Made in Europe",
      body: "AI models are hosted in Europe by European-owned companies.",
    },
    {
      icon: "functional/sparkles",
      title: "Curated models",
      body: "We've hand-picked the AI models that feel right in Eigin.",
    },
    {
      icon: "functional/euro",
      title: "What a credit is",
      body: "About one eurocent of AI usage. When you buy, we add the store fee and a small fee to keep Eigin running.",
    },
  ];
</script>

<!--
  How the relay works, in plain language: privacy, European hosting, curated
  models, and what a credit buys.

  The points are rows in a card, the same as the facts on the screen that
  opens this sheet. They answer the same kind of question, so they are told
  the same way — the sheet reads as more of that card, not as a brochure
  behind it.
-->
<Sheet bind:open title="Eigin Relay" description="The easy, private way to use cloud AI in Eigin.">
  {#snippet primary()}
    <div class="points">
      <ContentGroup>
        {#each points as point (point.title)}
          <Row title={point.title} description={point.body} icon={point.icon} accessory="none" />
        {/each}
      </ContentGroup>
    </div>
  {/snippet}
</Sheet>

<style>
  .points {
    /* Cards run to the page inset, as they do on a settings screen: the
       card is the wide thing and its own padding holds the content to the
       grid. The header above keeps the sheet's deeper text inset. */
    padding: 0 var(--spacing-n16);
  }
</style>
