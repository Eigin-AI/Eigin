<script lang="ts">
  import Icon from "../icon/Icon.svelte";

  let { value = $bindable(""), placeholder }: { value?: string; placeholder: string } = $props();
</script>

<!--
  The way in for people who already know what they want.

  A capsule with the glyph inside it, rather than a `TextInput`: search has no
  label to float, and its value is a query you throw away rather than a setting
  you commit.
-->
<label class="search">
  <Icon name="functional/search" size={20} />
  <input class="t-description" {placeholder} bind:value />
</label>

<style>
  .search {
    display: flex;
    /* The sheet body is a scrolling flex column, which would otherwise shrink
       the field to fit rather than scrolling past it. */
    flex: none;
    align-items: center;
    gap: var(--spacing-n8);
    box-sizing: border-box;
    height: var(--sizing-input-height);
    padding: 0 var(--sizing-input-px-left);
    border-radius: var(--radius-full);
    background: var(--color-input-standard-active);
    color: var(--color-text-standard-muted);
  }

  .search input {
    flex: 1;
    min-width: 0;
    border: none;
    background: transparent;
    color: var(--color-text-standard-base);
    font: inherit;
    outline: none;
  }
</style>
