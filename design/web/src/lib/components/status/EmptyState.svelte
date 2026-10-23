<script lang="ts">
  import Button from "../button/Button.svelte";
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";
  import "./screen-state.css";

  let {
    icon,
    title,
    description,
    action,
    onclick,
  }: {
    icon: IconName;
    title: string;
    description: string;
    /** Optional recovery or creation action. */
    action?: string;
    onclick?: () => void;
  } = $props();
</script>

<!-- A full-area absence of content, with an optional way forward. -->
<div class="eigin-screen-state">
  <span class="glyph" aria-hidden="true"><Icon name={icon} size="fill" /></span>
  <h2 class="t-titleS">{title}</h2>
  <p class="t-note">{description}</p>
  {#if action}<Button label={action} variant="secondary" size="medium" {onclick} />{/if}
</div>

<style>
  .glyph {
    display: flex;
    width: var(--spacing-n48);
    height: var(--spacing-n48);
    color: var(--color-icon-standard-muted);
  }
</style>
