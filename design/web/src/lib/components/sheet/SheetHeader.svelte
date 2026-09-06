<script lang="ts">
  import type { Snippet } from "svelte";
  import ActionButton from "../button/ActionButton.svelte";

  interface Props {
    title: string;
    /** Small step label above the title, e.g. "Step 1 of 3". */
    label?: string;
    description?: string;
    /** Rich description in place of the plain string; same slot and spacing. */
    descriptionContent?: Snippet;
    /** When set, shows the close button in the trailing corner. */
    onDismiss?: () => void;
  }

  const { title, label, description, descriptionContent, onDismiss }: Props = $props();
</script>

<!--
  The sheet's text block, with the optional close
  button trailing. With supporting text the block top-aligns against the
  button; title alone centres against it.
-->
<header class="header" class:tall={label || description || descriptionContent}>
  <div class="labels">
    {#if label}
      <span class="t-miniLabel label">{label}</span>
    {/if}
    <div class="lede">
      <h2 class="t-titleS title" id="title">{title}</h2>
      {#if descriptionContent}
        {@render descriptionContent()}
      {:else if description}
        <p class="t-description description">{description}</p>
      {/if}
    </div>
  </div>

  {#if onDismiss}
    <ActionButton
      icon="functional/x"
      variant="open"
      size="medium"
      label="Dismiss"
      onclick={onDismiss}
    />
  {/if}
</header>

<style>
  .header {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    padding: 0 var(--sizing-pageLayout-headerGrouping-px-mobile);
  }

  /* With supporting text, the block top-aligns with the close button. */
  .header.tall {
    align-items: flex-start;
  }

  .labels {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-headerGrouping-gap);
    flex: 1;
    min-width: 0;
  }

  .lede {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }

  /*
   * Header text keeps its natural line boxes: these gaps are measured to
   * untrimmed boxes on iOS, and nothing in a sheet needs cap-height alignment.
   */
  .title,
  .label,
  .description {
    text-box: normal;
    margin: 0;
    color: var(--color-text-standard-base);
  }

  .label,
  .description {
    color: var(--color-text-standard-muted);
  }

  /* iOS switches on horizontal size class; web has the full px scale. */
  @container eigin (min-width: 768px) {
    .header {
      padding: 0 var(--sizing-pageLayout-headerGrouping-px-tablet);
    }
  }

  @container eigin (min-width: 1280px) {
    .header {
      padding: 0 var(--sizing-pageLayout-headerGrouping-px-desktop);
    }
  }
</style>
