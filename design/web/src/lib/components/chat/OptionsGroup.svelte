<script lang="ts">
  import OptionsCarousel from "../card/OptionsCarousel.svelte";
  import type { OptionChoice } from "../card/types";

  let {
    question,
    options,
    somethingElse = { label: "Something else", description: "Write your own answer" },
    onSelect,
    onFocusInput,
  }: {
    /** Asked above the cards; omit when the question was already spoken. */
    question?: string;
    options: OptionChoice[];
    somethingElse?: { label: string; description: string };
    onSelect?: (label: string) => void;
    /** Taking the way out hands the turn back to the composer. */
    onFocusInput?: () => void;
  } = $props();
</script>

<!--
  The feed block that puts a question to you as
  cards. The cards and their exit belong to the carousel.
-->
<div class="options-group">
  {#if question}
    <p class="question t-chatMessage">{question}</p>
  {/if}

  <OptionsCarousel
    {options}
    {somethingElse}
    {onSelect}
    onSomethingElse={onFocusInput}
    inset="var(--chat-px-large)"
  />
</div>

<style>
  .options-group {
    display: flex;
    flex-direction: column;
    /* Question and cards stack at the feed's own message gap. */
    gap: var(--sizing-chat-gap-message);
    width: 100%;
  }

  .question {
    margin: 0;
    padding: 0 var(--chat-px-large);
    color: var(--color-text-standard-base);
  }
</style>
