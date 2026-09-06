<script lang="ts">
  import VisualCard from "./VisualCard.svelte";
  import type { OptionChoice, VisualCardVariant } from "./types";

  let {
    options,
    somethingElse,
    inset = "0px",
    gap = "var(--spacing-n12)",
    focus = "none",
    onSelect,
    onSomethingElse,
  }: {
    options: OptionChoice[];
    /** Trailing neutral card — the way out when none of the options fit. */
    somethingElse?: { label: string; description: string };
    /** Horizontal room around the run, so cards can scroll clear of the edge. */
    inset?: string;
    /** Space between cards. The chat feed uses n12, onboarding n16. */
    gap?: string;
    /** `center` snaps a card to the middle and scales its neighbours down,
        the way the onboarding priority carousel reads. */
    focus?: "none" | "center";
    /** Fires after the cards have played their exit. */
    onSelect?: (label: string) => void;
    onSomethingElse?: () => void;
  } = $props();

  /* The three impact variants cycle; the way out is always neutral. */
  const palette: VisualCardVariant[] = ["brand", "warm", "soft"];

  type Phase = { kind: "idle" } | { kind: "selecting"; label: string } | { kind: "collapsing" };
  let phase = $state<Phase>({ kind: "idle" });

  /** Reads a motion token in milliseconds so the exit stays in step with
      transitions when tokens change; the fallback backs reduced motion. */
  function tokenMs(name: string, fallback: number): number {
    const raw = getComputedStyle(document.documentElement).getPropertyValue(name);
    const value = parseFloat(raw);
    if (Number.isNaN(value)) return fallback;
    if (raw.includes("s") && !raw.includes("ms")) return value * 1000;
    return value;
  }

  /* Two phases: the others fall back first, then the whole run leaves. Picking
     an option never makes the cards vanish under your finger. */
  function choose(label: string) {
    if (phase.kind !== "idle") return;
    phase = { kind: "selecting", label };

    setTimeout(
      () => {
        phase = { kind: "collapsing" };
        setTimeout(() => onSelect?.(label), tokenMs("--motion-normal", 250));
      },
      tokenMs("--motion-fast", 150),
    );
  }

  function chosen(label: string) {
    return phase.kind === "selecting" && phase.label === label;
  }

  /* Neighbours scale to 0.88 and fade to 0.55 across an interactive scroll
     transition, so the ramp is continuous, not a step. */
  const PEEK_SCALE = 0.88;
  const PEEK_OPACITY = 0.55;

  let scroller = $state<HTMLDivElement>();

  /** Scales each card by how far its centre sits from the scroller's. */
  function trackFocus() {
    if (!scroller || focus !== "center") return;
    const middle = scroller.getBoundingClientRect().left + scroller.clientWidth / 2;
    for (const slot of scroller.querySelectorAll<HTMLElement>(".slot")) {
      const box = slot.getBoundingClientRect();
      const distance = Math.abs(box.left + box.width / 2 - middle);
      const away = Math.min(1, box.width > 0 ? distance / box.width : 0);
      slot.style.setProperty("--peek-scale", `${1 - (1 - PEEK_SCALE) * away}`);
      slot.style.setProperty("--peek-opacity", `${1 - (1 - PEEK_OPACITY) * away}`);
    }
  }

  $effect(() => {
    if (focus !== "center" || !scroller) return;
    trackFocus();
    const observer = new ResizeObserver(trackFocus);
    observer.observe(scroller);
    return () => observer.disconnect();
  });
</script>

<!--
  A horizontal scroller of visual
  cards with a neutral way out at the end.
-->
<div
  class="carousel"
  class:leaving={phase.kind === "collapsing"}
  class:centered={focus === "center"}
  style:--options-inset={inset}
  style:--options-gap={gap}
  bind:this={scroller}
  onscroll={trackFocus}
>
  <div class="run">
    {#each options as option, index (option.label)}
      <div class="slot" class:dimmed={phase.kind !== "idle" && !chosen(option.label)}>
        <VisualCard
          headline={option.label}
          explainer={option.description}
          symbol={option.symbol ?? "illustration/circle"}
          variant={palette[index % palette.length]}
          action={() => choose(option.label)}
        />
      </div>
    {/each}

    {#if somethingElse}
      <div class="slot" class:dimmed={phase.kind !== "idle"}>
        <VisualCard
          headline={somethingElse.label}
          explainer={somethingElse.description}
          symbol="functional/asterix"
          variant="neutral"
          action={onSomethingElse}
        />
      </div>
    {/if}
  </div>
</div>

<style>
  .carousel {
    width: 100%;
    container-type: inline-size;
    overflow-x: auto;
    scrollbar-width: none;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .carousel::-webkit-scrollbar {
    display: none;
  }

  .carousel.leaving {
    opacity: 0;
  }

  /* Centred focus: a card snaps to the middle and the run can reach the ends,
     so the first and last card can sit centre-stage too. */
  .carousel.centered {
    scroll-snap-type: x mandatory;
  }

  .carousel.centered .run {
    padding-inline: max(var(--options-inset), calc(50cqw - 150px));
  }

  .carousel.centered .slot {
    scroll-snap-align: center;
    transform: scale(var(--peek-scale, 1));
    opacity: var(--peek-opacity, 1);
  }

  /* The pick still dims and lifts; that overrides the peek ramp. */
  .carousel.centered .slot.dimmed {
    opacity: 0.35;
    transform: scale(0.95);
  }

  .run {
    display: flex;
    gap: var(--options-gap, var(--spacing-n12));
    width: max-content;
    /* Vertical room so a lifted card is not clipped by the scroller. */
    padding: var(--spacing-n4) var(--options-inset);
  }

  .slot {
    transition:
      opacity var(--motion-fast) var(--motion-easing-smooth),
      transform var(--motion-fast) var(--motion-easing-smooth);
  }

  .slot.dimmed {
    opacity: 0.35;
    transform: scale(0.95);
  }

  .carousel.leaving .slot {
    transform: scale(0.9);
  }

  @media (prefers-reduced-motion: reduce) {
    .carousel,
    .slot {
      transition: none;
    }
  }
</style>
