<script lang="ts">
  import { onDestroy } from "svelte";
  import { Button, MorphBlob, MorphIntensity, StreamThrottler, driveFrames } from "@lib";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  /**
   * What the wrist shows during a quick command. The phone does the thinking,
   * so these four are everything the watch ever says.
   */
  type Phase = "ready" | "listening" | "thinking" | "answered";

  let phase = $state<Phase>("ready");
  let spoken = $state("");
  let intensity = $state(MorphIntensity.none);
  /* Breathing is the blob's own, so it eases into the wobble rather than
     cutting out the moment the agent starts thinking. */
  let breath = $state(MorphIntensity.none);
  /* The answer arrives a word at a time; nothing to act on until it lands. */
  let streaming = $state(false);

  const reply = "Added milk to your personal shopping list.";

  const throttler = new StreamThrottler();
  let stopFrames: (() => void) | undefined;
  let timers: ReturnType<typeof setTimeout>[] = [];
  let rampUntil = 0;

  const labels: Record<Phase, string> = {
    ready: "Ready",
    listening: "Listening",
    thinking: "Thinking",
    answered: "Answered",
  };
  const options = ["Ready", "Listening", "Thinking", "Answered"] as const;
  let chosen = $state("Ready");

  /* What the blob is doing, and what the wearer can do about it. Only the
     answer has buttons; every other state is the blob and one line under it. */
  const prompt: Record<Phase, string> = {
    ready: "Tap to ask",
    listening: "Tap to send",
    thinking: "Thinking…",
    answered: "",
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
      (now) => {
        throttler.tick(now);
        spoken = throttler.displayedText;
        streaming = throttler.isRunning;
      },
      () => performance.now() / 1000 < rampUntil || throttler.isRunning,
    );
  }

  function setPhase(next: Phase) {
    const now = performance.now() / 1000;
    phase = next;
    chosen = labels[next];
    /* The blob wobbles only while the agent is working, and breathes while it
       waits for you — both ramp, so one becomes the other. */
    intensity = intensity.transitionedTo(next === "thinking", now);
    breath = breath.transitionedTo(next === "listening", now);
    rampUntil = now + 0.5;
    runFrames();
  }

  function showAnswer() {
    setPhase("answered");
    streaming = true;
    throttler.start();
    throttler.feed(reply);
    throttler.finish();
    runFrames();
  }

  /** Tapping the blob carries the command forward a step. */
  function advance() {
    clearTimers();
    if (phase === "ready") {
      setPhase("listening");
    } else if (phase === "listening") {
      setPhase("thinking");
      after(1800, showAnswer);
    }
  }

  function restart() {
    clearTimers();
    throttler.reset();
    spoken = "";
    streaming = false;
    setPhase("ready");
  }

  function jump(next: Phase) {
    clearTimers();
    throttler.reset();
    spoken = "";
    streaming = false;
    setPhase(next);
    if (next === "answered") showAnswer();
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
  The watch companion. Everything before the answer is the blob and a line
  under it, tapped anywhere to carry on; the answer replaces the blob with the
  words and the only two things worth doing with them.
-->
<div class="watch">
  {#if phase === "answered"}
    <p class="reply">{spoken}</p>
    <div class="actions" class:pending={streaming}>
      <Button label="Speak" variant="primary" size="extraSmall" onclick={() => {}} />
      <Button label="Ask again" variant="secondary" size="extraSmall" onclick={restart} />
    </div>
  {:else}
    <button class="stage" type="button" onclick={advance} aria-label={prompt[phase]}>
      <span class="blob">
        <MorphBlob {intensity} {breath} tempo={0.6} entryDelay={0.2} />
      </span>
      <span class="prompt t-body">{prompt[phase]}</span>
    </button>
  {/if}
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
     area is the target, so the wearer can tap without aiming. */
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
  }

  .blob {
    position: relative;
    width: 88px;
    height: 88px;
    display: grid;
    place-items: center;
  }

  .prompt {
    color: var(--color-text-standard-muted);
  }

  /* The answer is the content, so it takes the room the blob had. */
  .reply {
    flex: 1;
    font-size: 15px;
    line-height: 1.3;
    color: var(--color-text-standard-base);
    margin: 0;
  }

  .actions {
    display: grid;
    gap: var(--spacing-n8);
    padding-bottom: var(--spacing-n4);
    transition: opacity var(--duration-slow, 0.4s) ease;
  }

  /* Nothing to act on until the answer has finished arriving. */
  .actions.pending {
    opacity: 0;
    pointer-events: none;
  }

  /* Button heights are phone-scaled — the smallest is the only one that
     leaves the answer any room on a 224pt screen. Both span the width, so the
     pair reads as one stack rather than two tabs. */
  .actions :global(.eigin-btn) {
    width: 100%;
  }
</style>
