<script lang="ts">
  import Button from "./Button.svelte";
  import Icon from "../icon/Icon.svelte";
  import type { ButtonSize, ButtonVariant } from "./types";

  let {
    label,
    isChecked = false,
    variant = "secondary",
    size = "large",
    disabled = false,
    onclick,
  }: {
    label: string;
    isChecked: boolean;
    variant?: ButtonVariant;
    size?: ButtonSize;
    disabled?: boolean;
    onclick?: (event: MouseEvent) => void;
  } = $props();
</script>

<Button {label} {variant} {size} {disabled} {onclick}>
  {#snippet trailing()}
    <span class="indicator" class:checked={isChecked}>
      <Icon name="functional/check" size={14} />
    </span>
  {/snippet}
</Button>

<style>
  /* The marker: an outline square with a check tick when checked. */
  .indicator {
    box-sizing: border-box;
    width: 20px;
    height: 20px;
    border: 2px solid var(--color-icon-standard-muted);
    border-radius: 6px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: border-color var(--motion-normal) var(--motion-easing-smooth);
  }

  .indicator.checked {
    border-color: var(--color-icon-standard-base);
  }

  .indicator :global(svg) {
    opacity: 0;
    color: var(--color-icon-standard-base);
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .indicator.checked :global(svg) {
    opacity: 1;
  }
</style>
