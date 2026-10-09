<script lang="ts">
  import { tick } from "svelte";
  import ScreenPlaceholder from "@gallery/screens/ScreenPlaceholder.svelte";
  import { screenEntries } from "@gallery/screens/index";
  import ConversationScreen from "@gallery/showcase/ConversationScreen.svelte";
  import Headline from "@gallery/showcase/Headline.svelte";
  import { applyScroll } from "@gallery/showcase/scroll";
  import FlatLayout from "@gallery/showcase/layouts/FlatLayout.svelte";
  import TiltLayout from "@gallery/showcase/layouts/TiltLayout.svelte";
  import {
    backgroundOf,
    conversationScreen,
    headlineScale,
    sizeOf,
    type Shot,
  } from "@gallery/showcase/shots";

  let { shot, moving = false }: { shot: Shot; moving?: boolean } = $props();

  const size = $derived(sizeOf(shot));
  const background = $derived(backgroundOf(shot));
  const Screen = $derived(screenEntries.find((entry) => entry.id === shot.screen)?.component);
  const Layout = $derived(shot.layout === "flat" ? FlatLayout : TiltLayout);

  /* Holds the screen at the shot's scroll once its content has laid out.
     Clearing it returns to the top. */
  let canvas = $state<HTMLDivElement>();
  $effect(() => {
    const { scroll } = shot;
    const cleared = scroll === undefined;
    void [shot.screen, JSON.stringify(shot.conversation)];
    tick().then(() =>
      requestAnimationFrame(() => {
        if (!canvas) return;
        if (cleared && shot.screen !== conversationScreen) applyScroll(canvas, 0);
        else applyScroll(canvas, scroll);
      }),
    );
  });
</script>

<!-- One shot at its exact pixel size: what an export captures. -->
<div
  bind:this={canvas}
  class="shot-canvas"
  data-layout={shot.layout}
  style:width="{size.width}px"
  style:height="{size.height}px"
  style:--fill={background.fill}
>
  <Layout {shot} {size} {moving}>
    {#snippet screen()}
      {#if shot.screen === conversationScreen}
        <ConversationScreen
          turns={shot.conversation ?? []}
          pinToLatest={shot.scroll === undefined}
        />
      {:else if Screen}
        <Screen />
      {:else}
        <ScreenPlaceholder id={shot.screen} />
      {/if}
    {/snippet}
  </Layout>
  {#if shot.headline}
    <Headline
      text={shot.headline}
      at={shot.headlineAt}
      {size}
      ink={background.ink}
      scale={headlineScale(shot)}
    />
  {/if}
</div>

<style>
  /* A flat fill: the phone and its shadow carry the depth. */
  .shot-canvas {
    position: relative;
    overflow: hidden;
    flex: none;
    background: var(--fill);
  }
</style>
