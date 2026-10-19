<script lang="ts">
  import type { Snippet } from "svelte";
  import OnboardingSpeech from "@gallery/screens/onboarding/OnboardingSpeech.svelte";

  let {
    title,
    text,
    titleDelay,
    children,
  }: {
    title: string;
    text: string;
    titleDelay: number;
    /** The screen's interactive content, shown once the line has landed. */
    children: Snippet;
  } = $props();

  let spoken = $state("");

  /* Content waits until the line on screen has been said. */
  const revealed = $derived(spoken === text);
</script>

<!--
  One screen's worth of the agent speaking: its line, then the screen's
  content. The scaffold keys each screen's turn, so every screen starts laid
  out but unseen, and the outgoing one keeps its layout while it fades.
-->
<div class="turn">
  <OnboardingSpeech {title} {text} {titleDelay} onFinished={(line) => (spoken = line)} />

  <div class="content" class:revealed inert={!revealed}>
    {@render children()}
  </div>
</div>

<style>
  .turn {
    display: flex;
    flex: 1 0 auto;
    flex-direction: column;
    gap: var(--spacing-n24);
  }

  /* Bleeds to the screen edges so wide content, like the priority
     carousel's peeking cards, isn't clipped at the padding line. Moves by
     margin rather than transform: a transform would trap a step's sheets
     inside the content area. */
  .content {
    display: flex;
    flex-direction: column;
    flex: 1 0 auto;
    margin: 0 calc(-1 * var(--spacing-n24));
    padding: 0 var(--spacing-n24);
    margin-top: 8px;
    opacity: 0;
  }

  .content.revealed {
    margin-top: 0;
    opacity: 1;
    transition:
      opacity var(--motion-normal) ease-out,
      margin-top var(--motion-normal) ease-out;
  }
</style>
