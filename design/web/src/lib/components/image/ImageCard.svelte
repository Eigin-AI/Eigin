<script lang="ts">
  import Icon from "../icon/Icon.svelte";
  import SweepRing from "../status/SweepRing.svelte";
  import { linkHost } from "../link/types";
  import type { ImageState } from "./types";

  interface Props {
    /** The image to show. */
    src: string;
    /** Caption under the image, and the accessible name of the image itself. */
    alt?: string;
    /** When set, the card leads somewhere: tapping a loaded image follows it. */
    href?: string;
    /** Pins the state for the catalog. Left off, the card loads `src` and follows it. */
    state?: ImageState;
    /** Tap on an image that is not a link. */
    onOpen?: () => void;
    /** Tap on an image that is a link. */
    onFollowLink?: (href: string) => void;
    /** Tap on a withheld remote image. */
    onLoadRemote?: () => void;
  }

  /* Renamed on the way in: a local `state` would shadow the rune below. */
  const { src, alt, href, state: pinned, onOpen, onFollowLink, onLoadRemote }: Props = $props();

  let own = $state<ImageState>("loading");
  let ratio = $state<number | undefined>();

  const phase = $derived(pinned ?? own);
  /* A blocked or pinned-broken card must not reach for the network: the request
     is the thing being withheld. */
  const fetches = $derived(pinned === undefined || pinned === "loaded");
  /* The card takes the image's shape only while showing it; every other state
     keeps the placeholder square. Left unset rather than emptied: an empty
     custom property would invalidate the width rule and let the card
     full-bleed. */
  const shape = $derived(phase === "loaded" ? ratio : undefined);
  /* Empty where there is no host to name, as a data URI has none. */
  const host = $derived(linkHost(href ?? src));

  /* A new image starts over, rather than inheriting the last one's shape. */
  $effect(() => {
    void src;
    own = "loading";
    ratio = undefined;
  });

  function measure(event: Event) {
    const image = event.currentTarget as HTMLImageElement;
    ratio = image.naturalHeight > 0 ? image.naturalWidth / image.naturalHeight : undefined;
    own = "loaded";
  }

  const action = $derived.by(() => {
    if (phase === "failed") return undefined;
    if (phase === "blocked") return onLoadRemote;
    if (href) return () => onFollowLink?.(href);
    return onOpen;
  });

  const label = $derived.by(() => {
    if (phase === "blocked") return host ? `Show image from ${host}` : "Show image";
    if (href) return `Open ${host || href}`;
    return alt ? `View image: ${alt}` : "View image";
  });
</script>

<!--
  An image in a conversation, as a card.

  Height is fixed, for every image and every state, so the feed never moves: the
  shape an image turns out to be changes its width, not the space it sits in. It
  aspect-fills that box — cropped, never letterboxed or stretched.

  It grows in once, on arrival. The box is already reserved, so the reveal is a
  transform and pushes nothing around. Every change after it is a crossfade in
  place, out of a square placeholder that promised nothing.
-->
<figure class="image-card">
  <svelte:element
    this={action ? "button" : "div"}
    class="plate"
    class:tappable={action}
    class:revealed={phase === "loaded"}
    style={shape === undefined ? undefined : `--ratio:${shape}`}
    type={action ? "button" : undefined}
    role={action ? "button" : undefined}
    onclick={action}
    aria-label={action ? label : undefined}
  >
    {#if fetches}
      <img {src} alt={alt ?? ""} onload={measure} onerror={() => (own = "failed")} />
    {/if}

    <div class="cover" class:gone={phase === "loaded"}>
      {#if phase === "failed"}
        <span class="glyph notice"><Icon name="functional/warning" size={32} /></span>
        <span class="t-tag headline">This image didn't load</span>
        {#if host}<span class="t-tag detail">{host}</span>{/if}
      {:else if phase === "blocked"}
        <span class="glyph"><Icon name="functional/globe" size={32} /></span>
        <span class="t-tag headline">{host ? `Image from ${host}` : "Image from another site"}</span
        >
        <span class="t-tag detail">Tap to load it</span>
      {:else}
        <!-- No fraction to report: an image gives no progress until it is there. -->
        <SweepRing size={40} />
      {/if}
    </div>

    {#if href && host && phase === "loaded"}
      <span class="badge t-miniLabel">
        <Icon name="functional/globe" size={12} />
        <span class="badge-host">{host}</span>
      </span>
    {/if}
  </svelte:element>

  {#if alt}
    <figcaption class="t-tag">{alt}</figcaption>
  {/if}
</figure>

<style>
  .image-card {
    margin: 0;
    /* Left-anchored: a narrow image settles inward from the trailing edge,
       keeping its leading edge on the text column. */
    align-self: flex-start;
    width: 100%;
    animation: eigin-image-in var(--motion-slow) var(--motion-easing-gentle) both;
    transform-origin: left center;
  }

  .plate {
    --ratio: var(--sizing-image-ratio-placeholder);

    position: relative;
    /* Its own container, so the link badge can answer to the card's width
       rather than the screen's. */
    container: image / inline-size;
    box-sizing: border-box;
    display: block;
    /* Its own shape, never past the column and never past the cap — so a wide
       image fills the column, and a wide column gets a card, not a billboard.
       Until the image is measured this is the square placeholder, which the
       real shape grows out of. */
    width: min(
      100%,
      calc(
        var(--sizing-image-height) *
          clamp(var(--sizing-image-ratio-min), var(--ratio), var(--sizing-image-ratio-max))
      )
    );
    height: var(--sizing-image-height);
    padding: 0;
    border: none;
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-elevated);
    overflow: hidden;
    font-family: inherit;
    color: inherit;
    text-align: left;
    /* Delayed by the cover's own fade: the ring is gone before anything moves,
       and then the picture and the shape arrive as one. */
    transition: width var(--motion-slow) var(--motion-easing-gentle) var(--motion-normal);
  }

  .plate.tappable {
    cursor: pointer;
  }

  .plate.tappable::after {
    content: "";
    position: absolute;
    inset: 0;
    background: var(--color-interaction-light-hover);
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
    pointer-events: none;
  }

  .plate.tappable:hover::after {
    opacity: 1;
  }

  .plate.tappable:active {
    opacity: 0.75;
    transition: opacity var(--motion-fast) var(--motion-easing-snap);
  }

  img {
    display: block;
    width: 100%;
    height: 100%;
    /* Fill the box and crop; never letterbox, never distort. */
    object-fit: cover;
    opacity: 0;
    /* Held back by the cover's fade, like the width: the ring leaves first, then
       the picture arrives and the shape settles together. */
    transition: opacity var(--motion-normal) var(--motion-easing-smooth) var(--motion-normal);
  }

  .revealed img {
    opacity: 1;
  }

  .cover {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-n8);
    padding: var(--spacing-n16);
    text-align: center;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  /* Kept mounted so the image crossfades over it instead of replacing it. */
  .cover.gone {
    opacity: 0;
  }

  .glyph {
    display: inline-flex;
    color: var(--color-icon-standard-muted);
    /* A deeper breath than the default: a placeholder should sit back. */
    --pulse-depth: 0.4;
  }

  .glyph.notice {
    color: var(--color-icon-signal-notice);
  }

  .headline {
    color: var(--color-text-standard-base);
  }

  .detail {
    color: var(--color-text-standard-muted);
  }

  .badge {
    position: absolute;
    top: var(--spacing-n8);
    right: var(--spacing-n8);
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-n4);
    padding: var(--spacing-n4) var(--spacing-n8);
    max-width: calc(100% - var(--spacing-n16));
    border-radius: var(--radius-full);
    background: color-mix(in srgb, var(--color-surface-standard-base) 88%, transparent);
    color: var(--color-text-standard-base);
  }

  /* A narrow card truncates the host rather than hanging it over the edge. */
  .badge-host {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* Narrower still and the host is a stub worth nothing: the globe alone says
     the image leads somewhere, and the badge stays a badge. */
  @container image (max-width: 220px) {
    .badge-host {
      display: none;
    }
  }

  figcaption {
    margin-top: var(--spacing-n12);
    color: var(--color-text-standard-muted);
  }

  @keyframes eigin-image-in {
    from {
      opacity: 0;
      transform: scale(0.96);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .image-card {
      animation-name: eigin-image-fade;
    }

    .plate {
      transition: none;
    }
  }

  @keyframes eigin-image-fade {
    from {
      opacity: 0;
    }
  }
</style>
