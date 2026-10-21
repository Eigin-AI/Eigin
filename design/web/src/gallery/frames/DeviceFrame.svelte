<script lang="ts">
  import { EiginRoot } from "@lib";
  import GridOverlay from "@gallery/frames/GridOverlay.svelte";
  import StatusBar from "@gallery/frames/StatusBar.svelte";
  import { fitToWidth } from "@gallery/frames/fitToWidth";

  let {
    width = 393,
    height = 852,
    safeAreaTop = 59,
    safeAreaBottom = 34,
    safeAreaLeft = 0,
    safeAreaRight = 0,
    chrome = true,
    shape = "phone",
    grid = false,
    colorScheme = "system",
    fit = true,
    children,
  }: {
    /** Frame inner size in px. Phone is 393×852 (iPhone 17 Pro points); add
        tablet / desktop entries here when needed. */
    width?: number;
    /** A device height, or "content" for a canvas that hugs what it holds. */
    height?: number | "content";
    /** Status bar and home indicator insets, in points. */
    safeAreaTop?: number;
    safeAreaBottom?: number;
    safeAreaLeft?: number;
    safeAreaRight?: number;
    /** The phone's own status bar and home indicator. */
    chrome?: boolean;
    /** Which hardware to draw around the screen. */
    shape?: "phone" | "watch";
    /** Lays the active breakpoint's grid over the screen. */
    grid?: boolean;
    colorScheme?: "light" | "dark" | "system" | "inherit";
    /** Scales the frame down to fit its container. */
    fit?: boolean;
    children?: import("svelte").Snippet;
  } = $props();

  /* Bezel and chrome are the device. A canvas hugging its content is a
     fragment of a screen, not a phone on a stage, so it wears neither — it
     keeps only the width, the safe-area declarations and the root. */
  const isDevice = $derived(height !== "content");
  const fullDevice = $derived(chrome && isDevice);
  /* A watch has no island and no home indicator — only the time, which
     watchOS draws in the top inset rather than across a status bar. */
  const isWatch = $derived(shape === "watch");
</script>

<div class="device-fit" use:fitToWidth={fit}>
  <div
    class="device-frame"
    class:bare={!isDevice}
    class:watch={isWatch}
    style:width="{isDevice ? width + (isWatch ? 16 : 24) : width}px"
  >
    <div
      class="device-screen"
      class:fitted={height !== "content"}
      class:watch={isWatch}
      style:width="{width}px"
      style:height={height === "content" ? undefined : `${height}px`}
      style:--eigin-safe-area-top="{safeAreaTop}px"
      style:--eigin-safe-area-bottom="{safeAreaBottom}px"
      style:--eigin-safe-area-left="{safeAreaLeft}px"
      style:--eigin-safe-area-right="{safeAreaRight}px"
    >
      <EiginRoot {colorScheme}>
        {#if fullDevice && safeAreaTop > 0 && !isWatch}
          <StatusBar />
        {/if}

        {#if fullDevice && isWatch}
          <span class="watch-time" aria-hidden="true">9:41</span>
        {/if}

        <!-- The island is hardware: it turns with the phone. -->
        {#if fullDevice && !isWatch}
          <span class="island" class:on-edge={safeAreaLeft > 0} aria-hidden="true"></span>
        {/if}

        <div class="device-viewport">
          {@render children?.()}
          {#if grid}
            <!-- The scope resolves 2 columns on a phone, 4 above it. -->
            <GridOverlay columns={width >= 768 ? 4 : 2} />
          {/if}
        </div>

        {#if fullDevice && !isWatch}
          <span class="home-indicator" aria-hidden="true"></span>
        {/if}
      </EiginRoot>
    </div>
  </div>
</div>

<style>
  /* Takes the scaled size as its layout size, so the stage can centre it. */
  .device-fit {
    flex: none;
  }

  .device-fit > .device-frame {
    transform: scale(var(--fit-scale, 1));
    transform-origin: top left;
  }

  .device-frame {
    /* The bezel is the padding, so the declared width is the outside edge.
       flex-start keeps the stage from stretching the frame past the screen. */
    box-sizing: border-box;
    align-self: flex-start;
    padding: 12px;
    border-radius: 54px;
    /* Hardware bezel — constant across color schemes. */
    background: #141414;
    flex: none;
  }

  /* A fragment has no hardware around it, so a hairline marks where the
     phone's width ends — the page behind it is the same surface. */
  .device-frame.bare {
    padding: 0;
    background: none;
    border-radius: var(--radius-card);
  }

  .device-frame.bare > .device-screen {
    border-radius: var(--radius-card);
    box-shadow: inset 0 0 0 1px var(--color-border-standard-base);
  }

  /* The watch is mostly bezel, and its corners are far rounder against a
     much smaller screen, so the phone's fixed radii do not scale down. */
  .device-frame.watch {
    padding: 8px;
    border-radius: 44px;
  }

  .device-frame.watch > .device-screen {
    border-radius: 36px;
  }

  /* watchOS puts the time in the top inset instead of a status bar. */
  .device-screen :global(.watch-time) {
    position: absolute;
    top: 3px;
    right: 14px;
    z-index: 2;
    font-size: 13px;
    font-weight: 600;
    color: var(--color-text-standard-base);
    pointer-events: none;
  }

  .device-screen {
    border-radius: 42px;
    overflow: hidden;
    position: relative;
    background: var(--color-surface-standard-base);
    /* A no-op mask makes the screen a backdrop root: blurs inside it, like
       the soft edge, see only the screen and not the bezel behind its rounded
       corners. */
    mask-image: linear-gradient(black, black);
  }

  /* Hardware, so it stays black in either scheme. */
  .device-screen :global(.island) {
    position: absolute;
    top: 11px;
    left: 50%;
    transform: translateX(-50%);
    width: 125px;
    height: 36px;
    border-radius: var(--radius-full);
    background: #000;
    z-index: 2;
    pointer-events: none;
  }

  /* On its side the island sits against the long edge that gave way to it. */
  .device-screen :global(.island.on-edge) {
    top: 50%;
    left: 11px;
    transform: translateY(-50%);
    width: 36px;
    height: 125px;
  }

  /* The system draws this automatically to contrast with the content; the
     text colour tracks that across schemes. The island stays hard black —
     it is a camera cut-out, not a drawn bar. */
  .device-screen :global(.home-indicator) {
    position: absolute;
    bottom: 8px;
    left: 50%;
    transform: translateX(-50%);
    width: 140px;
    height: 5px;
    border-radius: var(--radius-full);
    background: var(--color-text-standard-base);
    opacity: 0.35;
    z-index: 1;
    pointer-events: none;
  }

  /* Screens scroll inside the frame, not inside the gallery page. The side
     insets pad the content while the root background runs under them, the
     way a screen behaves beside the island. */
  /* A fragment stands for a screen that continues past it, so it keeps a
     little room above and below rather than sitting on the bezel. */
  .device-screen:not(.fitted) .device-viewport {
    padding-block: var(--spacing-n24);
  }

  /* iOS overlays its scrollbars. A Mac set to always show them reserves a
     gutter instead, which narrows every screen in the frame by however wide
     that gutter is, so nothing inside the frame draws one. */
  .device-screen :global(*) {
    scrollbar-width: none;
  }

  .device-screen :global(*::-webkit-scrollbar) {
    display: none;
  }

  .device-viewport {
    position: relative;
    height: 100%;
    box-sizing: border-box;
    padding-left: var(--eigin-safe-area-left);
    padding-right: var(--eigin-safe-area-right);
    overflow-y: auto;
    container-type: inline-size;
  }

  /* EiginRoot wraps the viewport, so the height chain starts at the screen.
     Full height, not a minimum, so a screen can pin its own header and
     composer and scroll only the middle — the way it behaves on device. */
  .device-screen.fitted :global(.eigin-root),
  .device-screen.fitted :global(.eigin-scope) {
    height: 100%;
  }
</style>
