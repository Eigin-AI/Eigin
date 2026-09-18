<script lang="ts">
  import Icon from "../icon/Icon.svelte";

  interface Props {
    /** Two-way bindable presentation state. */
    open?: boolean;
    src: string;
    alt?: string;
    onDismiss?: () => void;
  }

  let { open = $bindable(false), src, alt, onDismiss }: Props = $props();

  /* Mounted from first presentation until the leave transition ends, as the
     sheet is, so closing can animate. */
  let mounted = $state(false);
  let visible = $state(false);
  let leaveTimer: ReturnType<typeof setTimeout> | undefined;

  $effect(() => {
    if (open) present();
    else if (mounted) leave();
  });

  function present() {
    clearTimeout(leaveTimer);
    mounted = true;
    requestAnimationFrame(() => (visible = true));
  }

  function leave() {
    visible = false;
    clearTimeout(leaveTimer);
    leaveTimer = setTimeout(() => (mounted = false), 400);
  }

  function dismiss() {
    open = false;
    onDismiss?.();
  }

  $effect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") dismiss();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  });
</script>

<!--
  One image, taking the screen.

  The conversation dims away and the picture is what is left: whole, uncropped,
  as large as the screen allows. It grows into place rather than cutting in.
  Anywhere outside the image dismisses, as does Escape.

  Anchors to the nearest positioned ancestor, like the sheet, so a phone frame
  can confine it.
-->
{#if mounted}
  <div class="viewer" class:visible role="dialog" aria-modal="true" aria-label={alt ?? "Image"}>
    <button class="backdrop" onclick={dismiss} aria-label="Close image"></button>
    <!-- The way out sits above the picture rather than on it, so nothing is
         drawn over the image. -->
    <div class="bar">
      <button class="chip close" onclick={dismiss} aria-label="Close">
        <Icon name="functional/x" size={24} />
      </button>
    </div>
    <div class="picture">
      <img {src} alt={alt ?? ""} />
    </div>
    {#if alt}
      <p class="caption t-tag">{alt}</p>
    {/if}
  </div>
{/if}

<style>
  .viewer {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-n16);
    padding: calc(var(--eigin-safe-area-top, 0px) + var(--spacing-n24)) var(--spacing-n24)
      calc(var(--eigin-safe-area-bottom, 0px) + var(--spacing-n16));
    box-sizing: border-box;
  }

  /* A dim, not a surface: the conversation stays visible underneath, darkened.
     Dark in both schemes, as the scrim behind a sheet is — so everything drawn
     on it is filled rather than tinted by the theme. */
  .backdrop {
    position: absolute;
    inset: 0;
    border: none;
    padding: 0;
    background: rgb(0 0 0 / 88%);
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-gentle);
    cursor: default;
  }

  .viewer.visible .backdrop {
    opacity: 1;
  }

  .picture {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
    min-height: 0;
    width: 100%;
  }

  /* Sized by the image itself, held inside the room available: the box is the
     picture, so the corners round the picture. The whole of it, however it is
     shaped — the crop belongs to the card. */
  img {
    max-width: 100%;
    max-height: 100%;
    border-radius: var(--radius-card);
    opacity: 0;
    transform: scale(0.94);
    transition:
      opacity var(--motion-normal) var(--motion-easing-smooth),
      transform var(--motion-slow) var(--motion-easing-gentle);
  }

  .viewer.visible img {
    opacity: 1;
    transform: scale(1);
  }

  /* The close chip brings its own ground, the way the card's link badge does:
     it has to read against whatever the picture puts behind it. */
  .chip {
    border: none;
    border-radius: var(--radius-full);
    background: color-mix(in srgb, var(--color-surface-standard-base) 88%, transparent);
    color: var(--color-text-standard-base);
  }

  /* The impact foreground: light in both schemes, as the dim is. */
  .caption {
    position: relative;
    margin: 0;
    max-width: 62ch;
    text-align: center;
    color: var(--color-text-impact-muted);
  }

  /* A button brings a UA font of its own; the caption keeps its type class. */
  .close {
    font-family: inherit;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: var(--sizing-button-action-extraSmall);
    height: var(--sizing-button-action-extraSmall);
    padding: 0;
    cursor: pointer;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .close:hover {
    opacity: 0.8;
  }

  .close:active {
    opacity: 0.6;
    transition: opacity var(--motion-fast) var(--motion-easing-snap);
  }

  .bar {
    position: relative;
    display: flex;
    justify-content: flex-end;
    align-self: stretch;
  }

  @media (prefers-reduced-motion: reduce) {
    img {
      transform: none;
      transition: opacity var(--motion-normal) var(--motion-easing-smooth);
    }
  }
</style>
