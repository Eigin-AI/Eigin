<script lang="ts">
  import { Icon, Sheet } from "@lib";
  import type { IconName } from "@lib";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* The pitch lives in the sheet's description; each point is an icon, a
     headline and a short body. */
  const points: { icon: IconName; title: string; body: string }[] = [
    {
      icon: "functional/lock",
      title: "Always private",
      body: "There's no Eigin account, and conversations are never stored or logged.",
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
      body: "One credit is about one eurocent of AI usage. Your purchase covers the platform fee and a small markup to keep Eigin running.",
    },
  ];
</script>

<!--
  How the relay works, in plain language: privacy, European hosting, curated
  models, and what a credit buys. Hugs its content, `fitsContent`-style
  presentation does.
-->
<Sheet bind:open title="Eigin Relay" description="The easy, private way to use cloud AI in Eigin.">
  {#snippet primary()}
    <div class="points">
      {#each points as point (point.title)}
        <section class="point">
          <h3 class="t-titleXS head">
            <Icon name={point.icon} size={18} />
            {point.title}
          </h3>
          <p class="t-description body">{point.body}</p>
        </section>
      {/each}
    </div>
  {/snippet}
</Sheet>

<style>
  .points {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n32);
    padding: 0 var(--sizing-pageLayout-headerGrouping-px-mobile);
  }

  .point {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n8);
  }

  .head {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    margin: 0;
    color: var(--color-text-standard-base);
  }

  .body {
    margin: 0;
    color: var(--color-text-standard-muted);
  }
</style>
