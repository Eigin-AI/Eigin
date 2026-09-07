<script lang="ts">
  import CardSurface from "../card/CardSurface.svelte";
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";

  const {
    tone = "info",
    title,
    body,
    onclick,
  }: {
    tone?: "info" | "warning" | "error";
    title: string;
    body: string;
    /** Makes the whole card a shortcut to the screen's own answer. */
    onclick?: () => void;
  } = $props();

  const icon = $derived<IconName>(tone === "info" ? "functional/info" : "functional/warning");
</script>

<!--
  Something the screen needs to tell you before you read the rest.

  It carries no action of its own. The screen already has one slot for the
  thing worth doing, and a fix inside the card competed with it: two ways to
  reconnect, in two different button languages, a few hundred points apart. So
  a notice raises the problem and the screen's primary action answers it, which
  also means the primary button always says something true.

  It is a card surface with a tone and a shape, so tapping it is the surface's
  own `action`: pressed, it fades like any other card. That shortcut leads to
  the same answer the screen already offers — not a second action, just the one
  below reached without scrolling past the problem to find it.
-->
<CardSurface action={onclick}>
  <div class="notice">
    <p class="t-titleXS head">
      <span class="glyph {tone}"><Icon name={icon} size={18} /></span>
      {title}
    </p>
    <p class="t-tag body">{body}</p>
  </div>
</CardSurface>

<style>
  .notice {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n8);
  }

  p {
    margin: 0;
  }

  .head {
    display: flex;
    align-items: center;
    gap: var(--spacing-n8);
    color: var(--color-text-standard-base);
  }

  .glyph {
    display: inline-flex;
    color: var(--color-icon-standard-base);
  }

  .glyph.warning {
    color: var(--color-icon-signal-notice);
  }

  .glyph.error {
    color: var(--color-icon-signal-negative);
  }

  .body {
    color: var(--color-text-standard-muted);
  }
</style>
