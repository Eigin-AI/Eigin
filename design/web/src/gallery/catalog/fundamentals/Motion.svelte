<script lang="ts">
  import "@lib/theme/pulse.css";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { Button, scaleGroups, motionEasings } from "@lib";

  const tiers = $derived(scaleGroups.find((group) => group.name === "motion")?.tokens ?? []);

  /* Each press sends the dots to the other side, so a tier's speed can be
     felt repeatedly rather than only on the first run. */
  let atEnd = $state(false);
  let pulseState = $state("running");
  let pulseDepth = $state("deep");
</script>

<div class="doc">
  <h2 class="t-titleM">Motion</h2>
  <p class="lede t-description">
    Three durations and three curves, from <code>design/tokens.json</code>. All zero under
    <code>prefers-reduced-motion</code>.
  </p>

  <div class="controls">
    <Button
      label="Play {atEnd ? 'left' : 'right'}"
      variant="secondary"
      size="extraSmall"
      onclick={() => (atEnd = !atEnd)}
    />
  </div>

  <h2 class="t-titleM">Duration</h2>
  <div class="rows">
    {#each tiers as tier (tier.name)}
      <div class="row">
        <div class="meta">
          <span class="name">{tier.name}</span>
          <span class="value">{tier.value}{tier.unit}</span>
        </div>
        <div class="track">
          <span
            class="dot"
            class:at-end={atEnd}
            style:transition-duration="var(--motion-{tier.name})"
            style:transition-timing-function="var(--motion-easing-smooth)"
          ></span>
        </div>
        <p class="note">{tier.description}</p>
      </div>
    {/each}
  </div>

  <h2 class="t-titleM">Easing</h2>
  <div class="rows">
    {#each motionEasings as easing (easing.name)}
      <div class="row">
        <div class="meta">
          <span class="name">{easing.name}</span>
          <span class="value">{easing.curve.replace("cubic-bezier", "")}</span>
        </div>
        <div class="track">
          <span
            class="dot"
            class:at-end={atEnd}
            style:transition-duration="var(--motion-slow)"
            style:transition-timing-function="var(--motion-easing-{easing.name})"
          ></span>
        </div>
        <p class="note">{easing.description}</p>
      </div>
    {/each}
  </div>

  <h2 class="t-titleM">Pulse</h2>
  <p class="lede t-description">
    Marks something as live — a tool running, a control waiting. One second, in and out, forever.
    Depth sets how far it dips; tool rows dip deeper.
  </p>
  <div class="controls">
    <OptionSelector options={["running", "still"]} bind:value={pulseState} />
    <OptionSelector options={["subtle", "deep"]} bind:value={pulseDepth} />
  </div>
  <div class="rows">
    <div class="row">
      <div class="meta">
        <span class="name">pulse</span>
        <span class="value">{pulseDepth === "deep" ? "0.4" : "0.7"}</span>
      </div>
      <span
        class="t-chatMessage pulse-sample"
        class:eigin-pulse={pulseState === "running"}
        style:--pulse-depth={pulseDepth === "deep" ? 0.4 : 0.7}
      >
        Searching the web
      </span>
      <p class="note">
        Depth is a property, not a token: iOS carries two copies of this animation at 0.7 and 0.4
        and notes the value should become a token.
      </p>
    </div>
  </div>
</div>

<style>
  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
  }

  .pulse-sample {
    color: var(--color-text-standard-base);
  }

  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  code {
    font-family: var(--font-mono);
    font-size: 0.9em;
  }

  .rows {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n24);
    margin-bottom: var(--spacing-n40);
  }

  .row {
    display: grid;
    grid-template-columns: 160px minmax(0, 1fr);
    align-items: center;
    gap: var(--spacing-n16);
  }

  .meta {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n4);
  }

  .name,
  .value {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--color-text-standard-muted);
  }

  .track {
    position: relative;
    height: 32px;
    border-radius: var(--radius-full);
    background: var(--color-surface-standard-alternative);
    overflow: hidden;
    container-type: inline-size;
  }

  .dot {
    position: absolute;
    top: 4px;
    left: 4px;
    width: 24px;
    height: 24px;
    border-radius: var(--radius-full);
    background: var(--color-accent);
    transition-property: transform;
  }

  .dot.at-end {
    transform: translateX(calc(100cqw - 32px));
  }

  .note {
    grid-column: 2;
    margin: 0;
    font-size: 12px;
    color: var(--color-text-standard-muted);
  }
</style>
