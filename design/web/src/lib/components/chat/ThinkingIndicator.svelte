<script lang="ts">
  import { untrack } from "svelte";
  import MorphBlob from "../morph/MorphBlob.svelte";
  import { MorphIntensity } from "../morph/intensity";
  import { stageAt, thinkingText, waitingForYouText } from "./thinkingCopy";

  interface Props {
    /** When this appearance began — anchors the shape cycle, entry and breath. */
    shownAt?: number;
    /** When the current thinking stretch began; null while stalled on the user. */
    clockStart?: number | null;
    /** Thinking seconds accumulated before the current stretch. */
    priorElapsed?: number;
    /** Whether the turn is parked waiting for the user. */
    stalled?: boolean;
  }

  const {
    shownAt = performance.now() / 1000,
    clockStart = performance.now() / 1000,
    priorElapsed = 0,
    stalled = false,
  }: Props = $props();

  /* The copy ladder only needs re-checking a few times a second; the blob
     drives its own frame loop. */
  let now = $state(performance.now() / 1000);
  $effect(() => {
    const id = setInterval(() => (now = performance.now() / 1000), 250);
    return () => clearInterval(id);
  });

  const elapsed = $derived((clockStart === null ? 0 : now - clockStart) + priorElapsed);
  const stage = $derived(stalled ? null : stageAt(elapsed));
  const label = $derived(stalled ? waitingForYouText : stage ? thinkingText[stage] : "");

  /* A crossfade in place: fading one element out and back keeps the feel
     without a structural swap, which would let the label animate itself
     while the indicator is leaving. */
  let shown = $state("");
  let fading = $state(true);

  $effect(() => {
    const next = label;
    if (next === untrack(() => shown)) return;
    // The first rung fades in like the rest: fading out an empty label is
    // invisible, so the same path gives the entry its fade.
    fading = true;
    const id = setTimeout(() => {
      shown = next;
      fading = false;
    }, 200);
    return () => clearTimeout(id);
  });
</script>

<div class="thinking">
  <!-- A fixed slot hugging the largest form, so the indicator sits flush with
       the assistant text edge. -->
  <div class="slot">
    <MorphBlob {shownAt} intensity={MorphIntensity.full} />
  </div>

  <!-- One element that swaps its text, so the label never plays its own
       transition while the indicator itself is leaving. -->
  <span class="label t-chatMessage" class:fading>{shown}</span>
</div>

<style>
  .thinking {
    display: flex;
    align-items: center;
    gap: var(--spacing-n12);
  }

  .slot {
    flex: none;
    width: 40px;
    height: 40px;
  }

  .label {
    color: var(--color-text-standard-muted);
    opacity: 0.6;
    transition: opacity 200ms var(--motion-easing-smooth);
  }

  .label.fading {
    opacity: 0;
  }
</style>
