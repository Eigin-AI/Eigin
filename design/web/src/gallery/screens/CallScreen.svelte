<script lang="ts">
  import { onDestroy } from "svelte";
  import { ActionButton, MorphBlob, MorphIntensity, StreamThrottler, driveFrames } from "@lib";
  import { overflowFade } from "@lib/internal/overflowFade";
  import type { IconName } from "@lib";

  type Phase = "idle" | "listening" | "processing" | "speaking";

  const speeds = [
    { id: "fast", label: "Fast", icon: "functional/speed/fast" as IconName },
    { id: "balanced", label: "Balanced", icon: "functional/speed/balanced" as IconName },
    { id: "slow", label: "Slow", icon: "functional/speed/slow" as IconName },
  ];
  let speedIndex = $state(1);
  const speed = $derived(speeds[speedIndex]);

  let phase = $state<Phase>("idle");
  let heard = $state("");
  let spoken = $state("");

  /* The blob wobbles while the agent thinks and settles the rest of the time. */
  let intensity = $state(MorphIntensity.none);
  let rampUntil = 0;

  const transcript = "Remind me what we agreed about Friday mornings";
  const reply =
    "You keep them clear until noon, every other week, and the first Friday of the month is yours whatever happens.";

  const throttler = new StreamThrottler();
  let stopFrames: (() => void) | undefined;
  let timers: ReturnType<typeof setTimeout>[] = [];

  function after(ms: number, run: () => void) {
    timers.push(setTimeout(run, ms));
  }

  function setPhase(next: Phase) {
    const now = performance.now() / 1000;
    phase = next;
    intensity = intensity.transitionedTo(next === "processing", now);
    /* The ramp takes the slow duration; keep frames coming until it lands. */
    rampUntil = now + 0.5;
    runFrames();
  }

  /* One driver for both the wobble ramp and the reveal. */
  function runFrames() {
    stopFrames?.();
    stopFrames = driveFrames(
      (now) => {
        throttler.tick(now);
        spoken = throttler.displayedText;
      },
      () => performance.now() / 1000 < rampUntil || throttler.isRunning,
    );
  }

  /* A scripted call, so the screen shows what each phase looks like. */
  function play() {
    for (const timer of timers) clearTimeout(timer);
    timers = [];
    heard = "";
    spoken = "";
    throttler.reset();
    setPhase("idle");

    after(1200, () => {
      setPhase("listening");
      heard = transcript;
    });
    after(3600, () => setPhase("processing"));
    after(5600, () => {
      setPhase("speaking");
      throttler.start();
      throttler.feed(reply);
      throttler.finish();
      runFrames();
    });
  }

  play();

  onDestroy(() => {
    stopFrames?.();
    for (const timer of timers) clearTimeout(timer);
  });

  const status = $derived.by(() => {
    if (phase === "idle") return { text: "Connecting…", muted: true };
    if (phase === "listening") return heard ? { text: heard } : { text: "Listening…", muted: true };
    if (phase === "processing") return { text: "Thinking…", muted: true };
    return spoken ? { text: spoken } : { text: "Speaking…", muted: true };
  });
</script>

<!--
  A live call: the agent as a blob, what is being said, and the controls.
  Presented full screen on iOS, so there is no header and no way back but
  hanging up.
-->
<div class="call">
  <div class="avatar">
    <MorphBlob
      {intensity}
      tempo={0.6}
      entryDelay={0.35}
      color="var(--color-surface-standard-elevated)"
    />
    <span class="emoji">🪶</span>
  </div>

  <div class="status" use:overflowFade>
    <p class="t-standfirst" class:muted={status.muted}>{status.text}</p>
  </div>

  <!-- Mirrors the inactive chat input bar: a capsule inset from the edges. -->
  <div class="pill-bar">
    <ActionButton
      icon={speed.icon}
      variant="primary"
      size="medium"
      label="Response speed: {speed.label}"
      onclick={() => (speedIndex = (speedIndex + 1) % speeds.length)}
    />
    <ActionButton
      icon="functional/phone_down"
      variant="destructive"
      size="medium"
      label="Hang up"
      onclick={play}
    />
    <ActionButton
      icon="functional/hand"
      variant="primary"
      size="medium"
      label="Interrupt"
      disabled={phase === "idle" || phase === "listening"}
      onclick={() => setPhase("listening")}
    />
  </div>
</div>

<style>
  .call {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .avatar {
    position: relative;
    align-self: center;
    flex: none;
    width: 140px;
    height: 140px;
    /* Measured from the safe area, not the top of the glass. */
    margin-top: calc(var(--eigin-safe-area-top, 0px) + var(--spacing-n48));
  }

  /*
    The face arrives after its body: the blob holds for 0.35s and takes 0.4s
    to scale in, so the emoji starts at 0.6s and lands just behind it. `snap`
    carries the same overshoot the blob's entry has, so the two read as one
    gesture rather than two.
  */
  .emoji {
    animation: emoji-entry var(--motion-normal) var(--motion-easing-snap) 0.6s both;
  }

  @keyframes emoji-entry {
    from {
      scale: 0;
    }
    to {
      scale: 1;
    }
  }

  /* Sized to the blob's narrowest form, so it never rides the edge. */
  .emoji {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 76px;
    line-height: 1;
  }

  .status {
    flex: 1;
    min-height: 0;
    overflow: hidden;
    padding: var(--spacing-n16) var(--spacing-n32);
    text-align: center;
  }

  /* Older lines rise into the fade, but only once there are lines to lose. */
  .status:global(.is-scrollable) {
    display: flex;
    flex-direction: column;
    justify-content: flex-end;
    mask-image: linear-gradient(to bottom, transparent 0, black var(--spacing-n40));
  }

  .status p {
    margin: 0;
    color: var(--color-text-standard-base);
  }

  .status p.muted {
    color: var(--color-text-standard-muted);
  }

  /* The motion tokens zero themselves under reduced motion, so the entry
     collapses to nothing; the fill mode would still hide it, so drop it. */
  @media (prefers-reduced-motion: reduce) {
    .emoji {
      animation: none;
    }
  }

  .pill-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--spacing-n16);
    flex: none;
    box-sizing: border-box;
    min-height: 64px;
    margin: 0 var(--spacing-n8) max(var(--spacing-n8), var(--eigin-safe-area-bottom, 0px));
    padding: var(--spacing-n8);
    border-radius: var(--radius-full);
    background: var(--color-surface-standard-elevated);
  }
</style>
