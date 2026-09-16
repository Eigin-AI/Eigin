<script lang="ts">
  import { onDestroy } from "svelte";
  import { MorphBlob, MorphIntensity, driveFrames } from "@lib";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  /**
   * The watch companion. Push-to-talk: the wearer presses anywhere and
   * holds, talks, and releasing sends. Fire-and-forget — the phone answers
   * by notification, so these three states are everything the watch ever
   * says. There is no reply screen: nothing on the wrist can hold the
   * display through a turn (Return to Clock), so the notification carries
   * the words and completion is a haptic.
   */
  type Phase = "ready" | "listening" | "sending";

  let phase = $state<Phase>("ready");
  /* The blob holds a still circle and pulses — per-frame shape morphing
     does not read at wrist size, but a scale pulse does. The pulse runs
     only while listening; the model ramps it in and out, so it never
     snaps on or off. */
  let pulse = $state(MorphIntensity.none);

  let timers: ReturnType<typeof setTimeout>[] = [];
  let stopFrames: (() => void) | undefined;
  let rampUntil = 0;

  const labels: Record<Phase, string> = {
    ready: "Ready",
    listening: "Listening",
    sending: "Sending",
  };
  const options = ["Ready", "Listening", "Sending"] as const;
  let chosen = $state("Ready");

  /* What the blob is doing, and what the wearer should do about it. */
  const prompt: Record<Phase, string> = {
    ready: "Push to talk",
    listening: "Release to send",
    sending: "Sending…",
  };

  function after(ms: number, run: () => void) {
    timers.push(setTimeout(run, ms));
  }

  function clearTimers() {
    for (const timer of timers) clearTimeout(timer);
    timers = [];
  }

  function runFrames() {
    stopFrames?.();
    stopFrames = driveFrames(
      () => {},
      () => performance.now() / 1000 < rampUntil,
    );
  }

  function setPhase(next: Phase) {
    const now = performance.now() / 1000;
    phase = next;
    chosen = labels[next];
    /* The pulse only runs while listening, ramped — one blob, still or
       breathing, never morphing. */
    pulse = pulse.transitionedTo(next === "listening", now);
    rampUntil = now + 0.6;
    runFrames();
  }

  /** Finishing the turn: completion is silent, and the wrist is ready again. */
  function settle() {
    setPhase("ready");
  }

  /** Pressing anywhere starts the recording. */
  function pressBegan() {
    if (phase !== "ready") return;
    setPhase("listening");
  }

  /** Releasing sends. A press with nothing said discards quietly. */
  function pressEnded() {
    if (phase !== "listening") return;
    setPhase("sending");
    after(2000, settle);
  }

  function jump(next: Phase) {
    clearTimers();
    setPhase(next);
    if (next === "sending") after(2000, settle);
  }

  $effect(() => {
    const next = (Object.keys(labels) as Phase[]).find((key) => labels[key] === chosen);
    if (next && next !== phase) jump(next);
  });

  useStageControls(() => controls);

  onDestroy(() => {
    stopFrames?.();
    clearTimers();
  });
</script>

{#snippet controls()}
  <OptionSelector options={[...options]} bind:value={chosen} />
{/snippet}

<!--
  The complication on the watch face is a plain launcher — it opens the app;
  it cannot hold a press, so it never starts a recording.
-->
<div class="watch">
  <button
    class="stage"
    type="button"
    onpointerdown={pressBegan}
    onpointerup={pressEnded}
    onpointerleave={pressEnded}
    aria-label={prompt[phase]}
  >
    <!-- Everything stays mounted and animates in place — no layout shift.
         The blob scales away while the question is in flight; the text
         follows it: in right after the blob lands, out after it leaves. -->
    <span class="blob" class:gone={phase === "sending"}>
      <MorphBlob
        intensity={MorphIntensity.none}
        breath={pulse}
        breathPulse={0.06}
        breathPeriod={3}
        entryDelay={0.2}
      />
    </span>
    <span class="prompt t-body" class:gone={phase === "sending"}>{prompt[phase]}</span>
  </button>
</div>

<style>
  .watch {
    display: flex;
    flex-direction: column;
    height: 100%;
    /* watchOS draws the time in the top inset, so content clears it. */
    padding: var(--eigin-safe-area-top, 0px) var(--spacing-n12) var(--spacing-n8);
    box-sizing: border-box;
  }

  /* The blob is the screen: centred, with its one line beneath it. The whole
     area is the target — hold anywhere, no aiming. */
  .stage {
    appearance: none;
    border: none;
    background: none;
    padding: 0;
    font: inherit;
    color: inherit;
    cursor: pointer;
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-n12);
    user-select: none;
    touch-action: none;
  }

  .blob {
    position: relative;
    width: 88px;
    height: 88px;
    display: grid;
    place-items: center;
    transition:
      opacity 0.4s ease,
      transform 0.4s ease;
  }

  .blob.gone {
    opacity: 0;
    transform: scale(0.1);
  }

  .prompt {
    color: var(--color-text-standard-muted);
    /* The text trails the blob: in after it lands, out after it leaves. */
    opacity: 1;
    transition: opacity 0.2s ease 0.35s;
  }

  .prompt.gone {
    opacity: 0;
    transition: opacity 0.2s ease 0.3s;
  }
</style>
