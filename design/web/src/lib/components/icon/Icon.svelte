<script lang="ts">
  import { icons, type IconName } from "../../generated/icons";

  let {
    name,
    size = 24,
  }: {
    name: IconName;
    /** Square size in px, or "fill" to take the container's size. */
    size?: number | "fill";
  } = $props();

  const box = $derived(size === "fill" ? "100%" : `${size}px`);
</script>

<span class="eigin-icon" style:width={box} style:height={box}>
  <!-- eslint-disable-next-line svelte/no-at-html-tags — generated, trusted content -->
  {@html icons[name]}
</span>

<style>
  .eigin-icon {
    display: inline-flex;
    flex: none;
  }
  .eigin-icon :global(svg) {
    width: 100%;
    height: 100%;
    display: block;
  }
</style>
