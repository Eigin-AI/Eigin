<script lang="ts">
  import { ChatInput, NavigationHeader } from "@lib";
  import SoftEdgeScroll from "@lib/internal/SoftEdgeScroll.svelte";

  const notes = [
    "Mornings stay clear until ten — nothing lands before that.",
    "Thursdays run long, so Friday starts slow on purpose.",
    "Travel weeks drop the evening block entirely.",
    "Deep work goes in the first block of the day, meetings after lunch.",
    "Reviews happen on paper first, screen second.",
    "Errands batch into a single afternoon, never spread across the week.",
    "Evenings are for reading, not for catching up on messages.",
    "Mondays are for planning, so nothing external is scheduled before noon.",
  ];

  let draft = $state("");

  /* Start mid-scroll so both soft edges sit over content. */
  let scroller = $state<HTMLElement>();

  $effect(() => {
    if (scroller) scroller.scrollTop = 120;
  });
</script>

<div class="doc">
  <h2 class="t-titleM">The soft edge</h2>
  <p class="lede t-description">
    Content should never hit a hard edge, and it should never compete with the controls above or
    below it. As it scrolls under a header or footer, it blurs away into it, with a light fade, and
    the controls stay clear on top. The blur does the work: content is unreadable behind a control
    and sharp again just past it.
  </p>

  <h2 class="t-titleM">Principles</h2>
  <ul class="lede t-description">
    <li><strong>Content recedes.</strong> It blurs away into the controls. It is never cut off.</li>
    <li>
      <strong>Controls stay sharp.</strong> The header, composer and tab bar sit above the soft edge.
    </li>
    <li>
      <strong>Only when there is more.</strong> At the end of the content, or when it all fits, there
      is nothing to soften, so there is no soft edge.
    </li>
    <li>
      <strong>No bar backgrounds.</strong> Headers and bars have no surface of their own. The screen is
      the only surface.
    </li>
    <li>
      <strong>One effect everywhere.</strong> Screens don't tune it. The same soft edge gives the same
      feel on every screen.
    </li>
  </ul>

  <div class="canvas">
    <div class="demo">
      <SoftEdgeScroll bind:scroller>
        {#snippet header()}
          <NavigationHeader title="Notes" />
        {/snippet}
        {#snippet footer()}
          <ChatInput bind:value={draft} isSendEnabled={false} onActionTap={() => {}} />
        {/snippet}
        <div class="notes">
          {#each notes as note, i (i)}
            <p class="t-chatMessage">{note}</p>
          {/each}
        </div>
      </SoftEdgeScroll>
    </div>
  </div>

  <h2 class="t-titleM">Using it</h2>
  <ul class="lede t-description">
    <li>
      Use it on every screen that scrolls under a header, composer or tab bar. In a sheet, the title
      block floats the same way and only the top edge softens. It uses the sheet shape, which
      reaches further, as the description below the title is taller than a header.
    </li>
    <li>
      Don't add a second fade, shadow or divider at the same edge. The soft edge is the separation.
    </li>
    <li>
      Collapsed content, like a long message, keeps its own end fade. That clips content. The soft
      edge softens scrolling.
    </li>
    <li>
      Build it with <code>SoftEdgeScroll</code>. Pass the header and footer as snippets. A footer
      that spaces itself, like the tab bar, takes <code>flushFooter</code>. A sheet passes
      <code>shape="sheet"</code> and <code>topOnly</code>.
    </li>
    <li>
      The shape, on a screen: full blur to 40% down the control, easing out by 16px past it; the
      fade starts at 50% and reaches 40px past it. On a sheet: full blur down the whole header,
      easing out by 44px past it; the fade reaches 52px. The blur is
      <code>--soft-edge-blur</code> (20px) with a <code>--soft-edge-wash</code> of the surface (35%),
      to match the iOS system blur.
    </li>
  </ul>
</div>

<style>
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  /* Phone-ish width, so the text wraps and the boxes overflow. */
  .demo {
    position: relative;
    width: 340px;
    height: 520px;
    overflow: hidden;
    background: var(--color-surface-standard-base);
    display: flex;
    flex-direction: column;
  }

  .notes {
    padding: 0 var(--spacing-n16);
  }

  .notes p {
    margin: 0 0 var(--spacing-n16);
    color: var(--color-text-standard-base);
  }
</style>
