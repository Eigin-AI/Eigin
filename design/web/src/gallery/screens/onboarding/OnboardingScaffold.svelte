<script lang="ts">
  import type { Snippet } from "svelte";
  import { fade } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import { driveFrames } from "@lib";
  import SoftEdgeScroll from "@lib/internal/SoftEdgeScroll.svelte";
  import OnboardingAvatar, {
    vesselSize as avatarVesselSize,
  } from "@gallery/screens/onboarding/OnboardingAvatar.svelte";
  import OnboardingTurn from "@gallery/screens/onboarding/OnboardingTurn.svelte";
  import { OPENED, TURN_FADE_MS, launchScale, opening } from "@gallery/screens/onboarding/opening";

  let {
    progress,
    showsProgress = true,
    entrance = false,
    turnId = "",
    title,
    text,
    titleDelay = 0,
    children,
  }: {
    progress: number;
    showsProgress?: boolean;
    /** Opens where the launch screen left the mark, then bounces up to its place. */
    entrance?: boolean;
    /** Identifies the current screen. A new value plays the screen change. */
    turnId?: string;
    title: string;
    text: string;
    titleDelay?: number;
    children: Snippet;
  } = $props();

  const AVATAR = 96;
  const SETTLED = { rise: 1, scale: 1, breath: 0, stretch: 0 };
  const LAUNCH_SCALE = launchScale(avatarVesselSize(AVATAR));

  /* Only the first screen opens; later ones keep the avatar in place. */
  // svelte-ignore state_referenced_locally
  const opens = entrance;
  let pose = $state(opens ? opening(0, LAUNCH_SCALE) : SETTLED);
  let height = $state(0);
  let slot = $state<HTMLElement>();

  $effect(() => {
    if (!opens) return;
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      pose = SETTLED;
      return;
    }
    let start = 0;
    let t = 0;
    return driveFrames(
      (now) => {
        start ||= now;
        t = now - start;
        pose = t < OPENED ? opening(t, LAUNCH_SCALE) : SETTLED;
      },
      () => t < OPENED,
    );
  });

  /* From the avatar's place to the middle of the screen, where the launch
     screen left the mark. */
  const toCentre = $derived(height / 2 - (slot?.offsetTop ?? 0) - AVATAR / 2);
</script>

<!--
  Shared chrome for the setup screens: the avatar at the top, its spoken line
  beneath, then the step's own content. One scaffold stays mounted across
  steps, so the avatar and its fill are continuous and each line reads as the
  same presence speaking. The layout is final from the first frame; only the
  avatar moves. A new `turnId` fades the old turn out over the new one, which
  is already laid out and waiting to speak. When a screen is too short for
  it all, the whole screen scrolls, avatar and line included.
-->
<div class="scaffold" bind:clientHeight={height}>
  <SoftEdgeScroll>
    <div class="content">
      <div
        class="avatar-slot"
        style:translate="0 {toCentre * (1 - pose.rise)}px"
        style:scale={pose.scale}
        style:visibility={pose.rise === 1 || height > 0 ? "visible" : "hidden"}
        bind:this={slot}
      >
        <OnboardingAvatar
          {progress}
          {showsProgress}
          animatesIn={!entrance}
          breath={pose.breath}
          stretch={pose.stretch}
          size={AVATAR}
        />
      </div>

      <!-- Stacked, so the outgoing and incoming turns overlap for one fade
       without moving anything. -->
      <div class="turns">
        {#key turnId}
          <div class="layer" out:fade={{ duration: TURN_FADE_MS, easing: cubicOut }}>
            <OnboardingTurn {title} {text} {titleDelay}>
              {@render children()}
            </OnboardingTurn>
          </div>
        {/key}
      </div>
    </div>
  </SoftEdgeScroll>
</div>

<style>
  /* Positioned, so a step's sheets present over the whole screen rather
     than scrolling with it. */
  .scaffold {
    position: relative;
    height: 100%;
    display: flex;
    flex-direction: column;
    background: var(--color-surface-standard-base);
    overflow: hidden;
  }

  .scaffold :global(.scroll) {
    scrollbar-width: none;
  }

  .content {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n24);
    box-sizing: border-box;
    min-height: 100%;
    padding: calc(var(--eigin-safe-area-top, 0px) + var(--spacing-n32)) var(--spacing-n24)
      calc(var(--eigin-safe-area-bottom, 0px) + var(--spacing-n32));
    overflow-x: hidden;
  }

  /* Above the turns, so the rising avatar never passes behind a title. */
  .avatar-slot {
    position: relative;
    z-index: 1;
  }

  /* Fills the room under the avatar, and grows past it when a turn needs more. */
  .turns {
    display: grid;
    flex: 1 0 auto;
    align-self: stretch;
  }

  .layer {
    display: flex;
    flex-direction: column;
    grid-area: 1 / 1;
  }
</style>
