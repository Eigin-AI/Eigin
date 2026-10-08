<script lang="ts">
  import { Button } from "@lib";
  import AgentHatch from "@gallery/screens/onboarding/AgentHatch.svelte";
  import { LANDS } from "@gallery/screens/onboarding/hatch";
  import OnboardingSpeech from "@gallery/screens/onboarding/OnboardingSpeech.svelte";
  import { spring } from "@gallery/screens/onboarding/spring";

  let {
    agentName,
    emoji,
    digest,
    speed = 1,
    onContinue,
  }: {
    agentName: string;
    emoji: string;
    /** The agent's constitution in a line or two, generated when it seals. */
    digest: string;
    /** Plays the hatch slower, for inspecting it. */
    speed?: number;
    onContinue?: () => void;
  } = $props();

  const HATCH = 140;
  /* The same settle the welcome avatar makes on its way up. */
  const rise = spring(0.4, 0.2);

  let landed = $state(false);
  let spoken = $state("");
  let height = $state(0);
  let slot = $state<HTMLElement>();
  const revealed = $derived(spoken === digest);

  /* While it hatches it is the only thing on screen, so it sits centred: the
     distance from its resting place to the middle. */
  const toCentre = $derived(height / 2 - (slot?.offsetTop ?? 0) - HATCH / 2);

  $effect(() => {
    const timer = setTimeout(() => (landed = true), (LANDS * 1000) / speed);
    return () => clearTimeout(timer);
  });
</script>

<!--
  The hero reveal, full-bleed over the chat when onboarding seals. The hatch
  plays out alone in the middle of the screen; once the face has landed it
  rises to the top, as the welcome avatar does, and only then does the agent
  name itself and say what it is for.
-->
<div class="reveal" bind:clientHeight={height}>
  <div
    class="slot"
    class:landed
    bind:this={slot}
    style:translate={landed ? "0 0" : `0 ${toCentre}px`}
    style:visibility={height > 0 ? "visible" : "hidden"}
    style:--rise-easing={rise.easing}
    style:--rise-ms="{rise.ms}ms"
  >
    <AgentHatch {emoji} {speed} size={HATCH} />
  </div>

  {#if landed}
    <!-- The name once it has risen, then a longer beat before the line. -->
    <OnboardingSpeech
      title="I am {agentName}."
      text={digest}
      titleDelay={500}
      streamDelay={1100}
      onFinished={(line) => (spoken = line)}
    />
  {/if}

  <div class="actions" class:revealed inert={!revealed}>
    <Button label="Continue" onclick={onContinue} />
  </div>
</div>

<style>
  .reveal {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n24);
    box-sizing: border-box;
    height: 100%;
    padding: calc(var(--eigin-safe-area-top, 0px) + var(--spacing-n32)) var(--spacing-n24)
      calc(var(--eigin-safe-area-bottom, 0px) + var(--spacing-n32));
    background: var(--color-surface-standard-base);
    /* The burst spills past the hatch; the screen edge is where it stops. */
    overflow: hidden;
  }

  .slot.landed {
    transition: translate var(--rise-ms) var(--rise-easing);
  }

  .actions {
    display: flex;
    flex-direction: column;
    align-self: stretch;
    margin-top: auto;
    opacity: 0;
    translate: 0 8px;
  }

  .actions.revealed {
    opacity: 1;
    translate: 0 0;
    transition:
      opacity var(--motion-slow) ease-out,
      translate var(--motion-slow) ease-out;
  }
</style>
