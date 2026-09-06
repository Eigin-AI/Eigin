<script lang="ts">
  import type { Snippet } from "svelte";
  import "./button.css";

  let {
    label,
    disabled = false,
    onclick,
    trailing,
  }: {
    label: string;
    disabled?: boolean;
    onclick?: (event: MouseEvent) => void;
    trailing?: Snippet;
  } = $props();
</script>

<!--
  A fixed-size capsule carrying the secondary button's colors and
  interaction states. Trailing sits right after the label (no spacer,
  unlike Button).
-->
<button class="eigin-btn secondary tag" {disabled} {onclick}>
  <span class="t-tag">{label}</span>
  {#if trailing}{@render trailing()}{/if}
</button>
