<script lang="ts">
  import { Button, Card, CardSurface, OptionsCarousel, VisualCard, Icon } from "../../../lib";
  import type { CardSize, OptionChoice, VisualCardVariant } from "../../../lib";
  import OptionSelector from "../OptionSelector.svelte";

  const cardSizes: CardSize[] = ["large", "small", "compact"];
  const visualVariants: VisualCardVariant[] = ["brand", "warm", "soft", "neutral"];
  const tap = ["inert", "tappable"] as const;

  let cardSize = $state<CardSize>("large");
  let cardTap = $state<(typeof tap)[number]>("inert");

  let visualVariant = $state<VisualCardVariant>("brand");
  let visualTap = $state<(typeof tap)[number]>("inert");

  let surfaceTap = $state<(typeof tap)[number]>("inert");

  const wayOut = ["offered", "withheld"] as const;
  let escape = $state<(typeof wayOut)[number]>("offered");

  const focusModes = ["free", "centered"] as const;
  let focusMode = $state<(typeof focusModes)[number]>("free");

  const choices: OptionChoice[] = [
    { label: "Start small", description: "One habit at a time", symbol: "illustration/root" },
    { label: "Go wide", description: "Try everything for a week", symbol: "illustration/wave" },
    { label: "Sleep on it", description: "Decide again tomorrow", symbol: "illustration/moon" },
  ];

  /* Selecting plays an exit, so the demo needs a way back. */
  let run = $state(0);
  let picked = $state<string | null>(null);

  const longExplainer =
    "Three things happened since you last checked in, and one of them might actually matter to you today. Tap to see the full digest whenever you have a minute.";
</script>

<div class="doc">
  <h2 class="t-titleM">Card</h2>
  <div class="controls">
    <OptionSelector options={cardSizes} bind:value={cardSize} />
    <OptionSelector options={tap} bind:value={cardTap} />
  </div>
  <div class="specimen">
    <Card
      headline="Headline goes here"
      explainer={cardSize === "large" ? longExplainer : "Explainer text goes right here"}
      size={cardSize}
      action={cardTap === "tappable" ? () => {} : undefined}
    >
      {#snippet image()}
        <div class="media-gradient"></div>
      {/snippet}
    </Card>
  </div>

  <h2 class="t-titleM">Visual card</h2>
  <div class="controls">
    <OptionSelector options={visualVariants} bind:value={visualVariant} />
    <OptionSelector options={tap} bind:value={visualTap} />
  </div>
  <div class="specimen">
    <VisualCard
      headline="Morning focus"
      explainer="One clear priority for the day."
      symbol="brand/avatar"
      variant={visualVariant}
      action={visualTap === "tappable" ? () => {} : undefined}
    />
  </div>

  <h2 class="t-titleM">Card surface</h2>
  <div class="controls">
    <OptionSelector options={tap} bind:value={surfaceTap} />
  </div>
  <div class="specimen">
    <CardSurface action={surfaceTap === "tappable" ? () => {} : undefined}>
      <div class="surface-content">
        <span class="rocket">🚀</span>
        <div class="surface-text">
          <span class="t-titleXS">Tappable card</span>
          <span class="t-tag muted">2 CHATS</span>
        </div>
        <span class="spacer"></span>
        <span class="arrow"><Icon name="functional/arrow/right" size={16} /></span>
      </div>
    </CardSurface>
  </div>
</div>

<h2 class="t-titleM">Options carousel</h2>
<p class="lede t-description">
  A choice put as cards you swipe through, cycling the three impact variants. The last card is the
  way out when none of them fit. Picking one dims the others before the whole run leaves, so nothing
  vanishes under your finger. Centred, a card snaps to the middle at full size and its neighbours
  scale back and fade, the way the onboarding priority carousel reads.
</p>

<div class="controls">
  <OptionSelector options={wayOut} bind:value={escape} />
  <OptionSelector options={focusModes} bind:value={focusMode} />
  <Button
    label={picked ? `Picked: ${picked}` : "Reset"}
    variant="secondary"
    size="extraSmall"
    onclick={() => {
      picked = null;
      run += 1;
    }}
  />
</div>

<div class="specimen carousel-specimen">
  {#key run}
    <OptionsCarousel
      options={choices}
      somethingElse={escape === "offered"
        ? { label: "Something else", description: "Write your own answer" }
        : undefined}
      focus={focusMode === "centered" ? "center" : "none"}
      gap={focusMode === "centered" ? "var(--spacing-n16)" : "var(--spacing-n12)"}
      onSelect={(label) => (picked = label)}
    />
  {/key}
</div>

<style>
  .controls {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    margin-bottom: var(--spacing-n16);
  }

  /* The run bleeds to the page edge, as it does to the screen edge in a feed. */
  .carousel-specimen {
    margin-bottom: var(--spacing-n40);
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
  }

  .specimen {
    padding: var(--spacing-n24);
    margin-bottom: var(--spacing-n40);
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-base);
    display: flex;
    justify-content: center;
  }

  /* A spot tint fading darker — read from the token so it follows schemes. */
  .media-gradient {
    background: linear-gradient(
      135deg,
      var(--color-button-spot-base),
      color-mix(in srgb, var(--color-button-spot-base) 65%, black)
    );
  }

  .surface-content {
    display: flex;
    align-items: center;
    /* Spaced n8 between items. */
    gap: var(--spacing-n8);
  }

  .rocket {
    font-size: 28px;
  }

  .surface-text {
    display: flex;
    flex-direction: column;
    /* VStack(spacing: 2) assumes untrimmed boxes, which renders
       as a ~12px visual gap; trimmed text needs that value directly. */
    gap: var(--spacing-n12);
  }

  .spacer {
    flex: 1;
  }

  .surface-text .muted,
  .arrow {
    color: var(--color-text-standard-muted);
  }

  .arrow {
    display: inline-flex;
  }
</style>
