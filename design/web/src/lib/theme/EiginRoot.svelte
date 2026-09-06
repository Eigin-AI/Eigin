<script lang="ts">
  import { MediaQuery } from "svelte/reactivity";
  import GridScope from "./GridScope.svelte";

  let {
    colorScheme = "system",
    children,
  }: {
    /** Resolved scheme, "system" to follow the OS, or "inherit" to follow an
        enclosing root — the case for a canvas placed inside the gallery. */
    colorScheme?: "light" | "dark" | "system" | "inherit";
    children?: import("svelte").Snippet;
  } = $props();

  const prefersDark = new MediaQuery("(prefers-color-scheme: dark)");

  const resolved = $derived.by(() => {
    if (colorScheme === "inherit") return undefined;
    if (colorScheme === "system") return prefersDark.current ? "dark" : "light";
    return colorScheme;
  });
</script>

<div class="eigin-root" data-color-scheme={resolved}>
  <GridScope>
    {@render children?.()}
  </GridScope>
</div>

<style>
  .eigin-root {
    background: var(--color-surface-standard-base);
    color: var(--color-text-standard-base);
    font-family: var(--font-ui);
    min-height: 100%;
  }

  /* Dragging a control must not select its label: the selection band read
     as a purple wash over a warm card. Copyable prose asks for it back. */
  .eigin-root :global(button) {
    -webkit-user-select: none;
    user-select: none;
    -webkit-tap-highlight-color: transparent;
  }

  /* The scope itself must not collapse the root's height. */
  .eigin-root > :global(.eigin-scope) {
    min-height: inherit;
  }
</style>
