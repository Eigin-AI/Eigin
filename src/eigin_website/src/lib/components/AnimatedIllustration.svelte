<script lang="ts">
  import type { Snippet } from "svelte";
  import { MediaQuery } from "svelte/reactivity";
  import { ActionButton } from "@eigin/ui";
  import { playWhenInView } from "../attachments/playWhenInView";

  /** An illustration with viewport-aware playback and an accessible pause control. */
  let {
    class: className = "",
    labels,
    children,
  }: {
    class?: string;
    labels: { pause: string; play: string };
    children: Snippet<[boolean]>;
  } = $props();
  let paused = $state(false);
  let active = $state(false);
  let mounted = $state(false);
  const reduced = new MediaQuery("(prefers-reduced-motion: reduce)");
  $effect(() => {
    mounted = true;
  });
</script>

<div
  class="animated-illustration {className}"
  {@attach playWhenInView(paused || reduced.current, (value) => (active = value))}
>
  {@render children(active)}
  {#if mounted && !reduced.current}
    <div class="illustration-playback">
      <ActionButton
        icon={paused ? "brand/play" : "brand/pause"}
        label={paused ? labels.play : labels.pause}
        size="extraSmall"
        variant="elevated"
        onclick={() => (paused = !paused)}
      />
    </div>
  {/if}
</div>

<style>
  .animated-illustration {
    position: relative;
  }
  .animated-illustration:not([data-active="true"]) :global(*) {
    animation-play-state: paused !important;
  }
  .illustration-playback {
    position: absolute;
    bottom: var(--spacing-n8);
    right: var(--spacing-n8);
    z-index: 1;
  }
</style>
