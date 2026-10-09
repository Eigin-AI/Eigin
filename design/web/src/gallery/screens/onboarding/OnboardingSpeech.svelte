<script lang="ts">
  import { untrack } from "svelte";
  import { pause, speak } from "@gallery/screens/onboarding/speak";
  import { CONTENT_DELAY_MS, STREAM_DELAY_MS } from "@gallery/screens/onboarding/opening";

  let {
    title,
    text,
    titleDelay = 0,
    streamDelay = STREAM_DELAY_MS,
    onFinished,
  }: {
    title: string;
    text: string;
    /** Beat in ms before the title appears, letting the avatar land first. */
    titleDelay?: number;
    /** Beat in ms between the title appearing and the body streaming. */
    streamDelay?: number;
    /** Called with `text` a beat after it has finished streaming. */
    onFinished?: (text: string) => void;
  } = $props();

  let titleShown = $state(false);
  let shown = $state("");

  /* Replays only when the words change. A derived string settles on equal
     values, so a parent recomputing the same line doesn't restart it. */
  const line = $derived(`${title}\u0001${text}`);

  $effect(() => {
    void line;
    const said = untrack(() => text);
    const delay = untrack(() => titleDelay);
    const controller = new AbortController();
    const { signal } = controller;
    titleShown = false;
    shown = "";

    (async () => {
      await pause(delay, signal);
      if (signal.aborted) return;
      titleShown = true;
      await pause(streamDelay, signal);
      await speak(said, (next) => (shown = next), signal);
      // A beat after the line lands before the screen's content appears.
      await pause(CONTENT_DELAY_MS, signal);
      if (!signal.aborted) onFinished?.(said);
    })();

    return () => controller.abort();
  });
</script>

<!--
  The avatar's spoken line: a title that drops in, then the body streamed as
  the chat streams. The whole line is laid out from the start with the unsaid
  part transparent, so words land in place instead of reflowing.
-->
<div class="speech">
  <h2 class="t-titleM title" class:shown={titleShown}>{title}</h2>
  <p class="t-standfirst body">
    <span>{shown}</span><span class="unsaid">{text.slice(shown.length)}</span>
  </p>
</div>

<style>
  .speech {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n12);
    width: 100%;
    text-align: center;
  }

  .title {
    margin: 0;
    color: var(--color-text-standard-base);
    opacity: 0;
    translate: 0 -8px;
  }

  .title.shown {
    opacity: 1;
    translate: 0 0;
    transition:
      opacity 450ms ease-out,
      translate 450ms ease-out;
  }

  .body {
    margin: 0;
    color: var(--color-text-standard-muted);
    white-space: pre-line;
  }

  .unsaid {
    color: transparent;
  }
</style>
