<script lang="ts">
  import type { Snippet } from "svelte";
  import OnboardingAvatar from "@gallery/screens/onboarding/OnboardingAvatar.svelte";
  import OnboardingSpeech from "@gallery/screens/onboarding/OnboardingSpeech.svelte";
  import { spring } from "@gallery/screens/onboarding/spring";

  let {
    progress,
    showsProgress = true,
    entrance = false,
    title,
    text,
    titleDelay = 0,
    children,
  }: {
    progress: number;
    showsProgress?: boolean;
    /** Opens on the avatar already centred, holding a beat before it moves up. */
    entrance?: boolean;
    title: string;
    text: string;
    titleDelay?: number;
    children: Snippet;
  } = $props();

  const AVATAR = 96;
  const settle = spring(0.4, 0.2);

  // svelte-ignore state_referenced_locally
  let landed = $state(!entrance);
  let spoken = $state("");
  let height = $state(0);

  /* Content waits until the line on screen has been said. */
  const revealed = $derived(spoken === text);

  $effect(() => {
    if (landed) return;
    const timer = setTimeout(() => (landed = true), 1500);
    return () => clearTimeout(timer);
  });

  /* While landing the avatar is the only thing on screen, so it sits centred:
     the distance from its resting place to the middle. */
  let slot = $state<HTMLElement>();
  const toCentre = $derived(height / 2 - (slot?.offsetTop ?? 0) - AVATAR / 2);
</script>

<!--
  Shared chrome for the setup screens: the avatar at the top, its spoken line
  beneath, then the step's own content. One scaffold stays mounted across
  steps, so the avatar and its fill are continuous and each line reads as the
  same presence speaking.
-->
<div class="scaffold" bind:clientHeight={height}>
  <div
    class="avatar-slot"
    class:landed
    style:translate={landed ? "0 0" : `0 ${toCentre}px`}
    style:scale={landed ? 1 : 1.5}
    style:visibility={landed || height > 0 ? "visible" : "hidden"}
    style:--settle-easing={settle.easing}
    style:--settle-ms="{settle.ms}ms"
    bind:this={slot}
  >
    <OnboardingAvatar {progress} {showsProgress} animatesIn={!entrance} size={AVATAR} />
  </div>

  {#if landed}
    <div class="speech">
      <OnboardingSpeech {title} {text} {titleDelay} onFinished={(line) => (spoken = line)} />
    </div>

    <div class="content" class:revealed inert={!revealed}>
      {@render children()}
    </div>
  {/if}
</div>

<style>
  /* Positioned, so a step's sheets present over the whole screen. */
  .scaffold {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n24);
    box-sizing: border-box;
    height: 100%;
    padding: calc(var(--eigin-safe-area-top, 0px) + var(--spacing-n32)) var(--spacing-n24)
      calc(var(--eigin-safe-area-bottom, 0px) + var(--spacing-n32));
    background: var(--color-surface-standard-base);
    overflow: hidden;
  }

  .avatar-slot.landed {
    transition:
      translate var(--settle-ms) var(--settle-easing),
      scale var(--settle-ms) var(--settle-easing);
  }

  .speech {
    width: 100%;
    animation: fade-in var(--motion-slow) ease-out both;
  }

  /* Bleeds to the screen edges so wide content, like the priority
     carousel's peeking cards, isn't clipped at the padding line. Moves by
     margin rather than transform: a transform would trap a step's sheets
     inside the content area. */
  .content {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    align-self: stretch;
    margin: 0 calc(-1 * var(--spacing-n24));
    padding: 0 var(--spacing-n24);
    overflow-y: auto;
    margin-top: 8px;
    opacity: 0;
  }

  /* Only the reveal animates: a step change hides the old content at once. */
  .content.revealed {
    margin-top: 0;
    opacity: 1;
    transition:
      opacity var(--motion-normal) ease-out,
      margin-top var(--motion-normal) ease-out;
  }

  @keyframes fade-in {
    from {
      opacity: 0;
    }
  }
</style>
