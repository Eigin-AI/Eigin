<script lang="ts">
  import {
    Button,
    ExternalLinkSheet,
    GridScope,
    ImageCard,
    ImageViewer,
    SubtleActionButton,
    Icon,
  } from "@lib";
  import type { ImageState } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { scene } from "@gallery/catalog/sampleScene";

  const shapes = {
    panorama: scene(1600, 600),
    landscape: scene(1600, 900),
    square: scene(1200, 1200),
    portrait: scene(900, 1600),
  } as const;

  const shapeNames = ["landscape", "panorama", "square", "portrait"] as const;
  let shape = $state<(typeof shapeNames)[number]>("landscape");

  const stateNames = ["live", "withheld", "loading", "loaded", "broken"] as const;
  let which = $state<(typeof stateNames)[number]>("live");

  const pinned: Record<(typeof stateNames)[number], ImageState | undefined> = {
    live: undefined,
    withheld: "blocked",
    loading: "loading",
    loaded: "loaded",
    broken: "failed",
  };

  const captions = ["caption", "no caption"] as const;
  let caption = $state<(typeof captions)[number]>("caption");

  const links = ["plain", "linked"] as const;
  let link = $state<(typeof links)[number]>("plain");

  /* Remounts the card so the entrance can be watched again. Nothing else
     remounts it: switching a control changes the card's state, and a state
     change is a crossfade in place. */
  let replay = $state(0);

  /* The specimen's own slow connection. A drawn scene arrives in the same frame
     it is asked for, which hides the whole point: the placeholder, the fade,
     and the shape settling out of the square. */
  let arriving = $state(true);
  $effect(() => {
    void replay;
    void which;
    void shape;
    arriving = true;
    const timer = setTimeout(() => (arriving = false), 1600);
    return () => clearTimeout(timer);
  });

  let viewing = $state(false);
  let leaving = $state(false);
</script>

<div class="doc">
  <h2 class="t-titleM">Image card</h2>
  <p class="lede t-description">
    An image in a reply, as a card. Every image is the same height, so the feed never moves — only
    the width changes. The image fills the box and is cropped. Alt text is the caption.
  </p>
  <p class="lede t-description">
    It grows in once, on arrival. After that every change is a crossfade in place. The placeholder
    is square; the real shape grows out of it.
  </p>
  <p class="lede t-description">
    <strong>Withheld</strong> comes before loading. The model wrote the URL, so fetching it tells that
    host you are here. Holding the fetch makes it your call.
  </p>

  <div class="controls">
    <OptionSelector options={stateNames} bind:value={which} />
    <OptionSelector options={shapeNames} bind:value={shape} />
    <OptionSelector options={captions} bind:value={caption} />
    <OptionSelector options={links} bind:value={link} />
    <Button label="Play it again" variant="secondary" size="small" onclick={() => (replay += 1)} />
  </div>

  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="stack">
        {#key replay}
          <ImageCard
            src={shapes[shape]}
            alt={caption === "caption" ? "The valley at the end of the long walk" : undefined}
            href={link === "linked" ? "https://en.wikipedia.org/wiki/Valley" : undefined}
            state={which === "live" && arriving ? "loading" : pinned[which]}
            onOpen={() => {}}
            onFollowLink={() => {}}
            onLoadRemote={() => (which = "live")}
          />
        {/key}
      </div>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">One height, any shape</h2>
  <p class="lede t-description">
    All four start square and settle. Wide fills the column and stops at double width. Tall settles
    inward and stops at three-quarter — a tall image never grows down the screen.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="stack">
        {#each shapeNames as name (name)}
          <ImageCard src={shapes[name]} alt={name} onOpen={() => {}} />
        {/each}
      </div>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Opening one</h2>
  <p class="lede t-description">
    Tapping an image that is not a link opens it full screen, uncropped — the crop belongs to the
    card, which has a place to hold in the feed. Tapping an image that <em>is</em> a link leaves Eigin
    instead, and says so first: a reply's links were chosen by the model, not by you, so the host is named
    and leaving is a second, deliberate tap.
  </p>
  <div class="phone">
    <GridScope>
      <div class="tries">
        <SubtleActionButton label="Open full screen" onclick={() => (viewing = true)}>
          {#snippet icon()}<Icon name="functional/grid" size={24} />{/snippet}
        </SubtleActionButton>
        <SubtleActionButton label="Follow a linked image" onclick={() => (leaving = true)}>
          {#snippet icon()}<Icon name="functional/globe" size={24} />{/snippet}
        </SubtleActionButton>
        <div class="one">
          <ImageCard
            src={shapes.portrait}
            alt="Tap the card itself — it does the same thing"
            onOpen={() => (viewing = true)}
          />
        </div>
      </div>

      <ImageViewer
        bind:open={viewing}
        src={shapes.portrait}
        alt="The valley at the end of the long walk"
      />
      <ExternalLinkSheet bind:open={leaving} href="https://en.wikipedia.org/wiki/Valley" />
    </GridScope>
  </div>
</div>

<style>
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
    max-width: 100%;
  }

  /* Stands in for a phone column, like the chat catalog. */
  .stack {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    padding: 0 var(--sizing-chat-px-large-mobile);
  }

  /* The mock screen the viewer and the sheet present over. */
  .phone {
    position: relative;
    width: 393px;
    height: 640px;
    background: var(--color-surface-standard-base);
    border-radius: var(--radius-card);
    outline: 1px dashed var(--color-border-standard-base);
    margin-bottom: var(--spacing-n40);
    overflow: hidden;
  }

  .tries {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
    padding: var(--spacing-n24);
  }

  .one {
    display: flex;
  }
</style>
