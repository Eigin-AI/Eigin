<script lang="ts">
  import { Button, MorphBlob, MorphIntensity, morphFormPath, morphForms } from "@lib";

  /* Restarting the clock replays the entry pop and reseeds the cycle. */
  let shownAt = $state(performance.now() / 1000);
  const replay = () => (shownAt = performance.now() / 1000);

  let engaged = $state(true);
  let changedAt = $state(performance.now() / 1000);
  const intensity = $derived(new MorphIntensity(engaged, changedAt));
  function toggleIntensity() {
    changedAt = performance.now() / 1000;
    engaged = !engaged;
  }

  const sizes = [
    { label: "chat 40", px: 40 },
    { label: "80", px: 80 },
    { label: "voice 160", px: 160 },
  ];
</script>

<div class="doc">
  <h2 class="t-titleM">Morph Blob</h2>
  <p class="lede t-description">
    Eigin's presence. It pops in, then drifts between near-circles, breathing between moves and
    never repeating a run. Set it still and it relaxes to a circle.
  </p>

  <div class="controls">
    <Button label="Replay entry" variant="secondary" size="extraSmall" onclick={replay} />
    <Button
      label={engaged ? "Settle to circle" : "Start wobbling"}
      variant="secondary"
      size="extraSmall"
      onclick={toggleIntensity}
    />
  </div>

  <div class="row">
    {#each sizes as size (size.px)}
      <div class="slot">
        <div style:width="{size.px}px" style:height="{size.px}px">
          <MorphBlob {shownAt} {intensity} tempo={size.px > 100 ? 0.6 : 1} />
        </div>
        <span class="caption">{size.label}</span>
      </div>
    {/each}
  </div>

  <h2 class="t-titleM">Form Library</h2>
  <p class="lede t-description">
    The forms it drifts between — one circle shifting its weight. Each run takes its own order and
    comes home to the first.
  </p>
  <div class="library">
    {#each morphForms.map((_, i) => i) as i (i)}
      <div class="form">
        <svg viewBox="0 0 100 100" aria-hidden="true">
          <path d={morphFormPath(i)} fill="var(--color-button-spot-base)" />
        </svg>
        <span class="index">{i}</span>
      </div>
    {/each}
  </div>
</div>

<style>
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  .controls {
    display: flex;
    gap: var(--spacing-n8);
    margin-bottom: var(--spacing-n24);
  }

  .row {
    display: flex;
    align-items: flex-end;
    gap: var(--spacing-n40);
    margin-bottom: var(--spacing-n40);
  }

  .slot {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n8);
  }

  .caption,
  .index {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--color-text-standard-muted);
  }

  .library {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-n24);
  }

  .form {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n4);
  }

  .form svg {
    display: block;
    width: 48px;
    height: 48px;
  }
</style>
