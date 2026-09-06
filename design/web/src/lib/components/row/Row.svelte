<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";

  interface Props {
    title: string;
    /** Supporting line under the title. */
    description?: string;
    /** Current setting, shown at the trailing edge. Truncates rather than wraps. */
    value?: string;
    /** Leading glyph. */
    icon?: IconName;
    /** What the row promises: navigation, an external link, or nothing. */
    accessory?: "chevron" | "link" | "none";
    /** A control in place of the accessory — a switch, a small button. */
    trailing?: Snippet;
    onclick?: () => void;
  }

  const {
    title,
    description,
    value,
    icon,
    accessory = "chevron",
    trailing,
    onclick,
  }: Props = $props();

  const interactive = $derived(Boolean(onclick));
  const showsAccessory = $derived(!trailing && accessory !== "none");
</script>

<!--
  One row of a content group: an optional leading glyph, the title with an
  optional supporting line, an optional value, and a trailing accessory or
  control.

  Web-first: iOS repeats this layout by hand on every settings screen rather
  than sharing a component.
-->
{#snippet contents()}
  {#if icon}
    <span class="glyph"><Icon name={icon} size={24} /></span>
  {/if}

  <span class="labels">
    <span class="t-titleXS title">{title}</span>
    {#if description}
      <span class="t-tag description">{description}</span>
    {/if}
  </span>

  {#if value}
    <span class="t-tag value">{value}</span>
  {/if}

  {#if trailing}
    {@render trailing()}
  {:else if showsAccessory}
    <span class="accessory" class:chevron={accessory === "chevron"}>
      <Icon
        name={accessory === "chevron" ? "functional/chevron/down" : "functional/arrow/up_right"}
        size={16}
      />
    </span>
  {/if}
{/snippet}

<!-- A row that does something is a button; a row that only states something is
     a plain element, so it never sits in the tab order promising an action. -->
{#if interactive}
  <button class="eigin-row interactive" type="button" {onclick}>
    {@render contents()}
  </button>
{:else}
  <div class="eigin-row">
    {@render contents()}
  </div>
{/if}

<style>
  .eigin-row {
    position: relative;
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    width: 100%;
    box-sizing: border-box;
    padding: var(--spacing-n16) var(--spacing-n24);
    background: transparent;
    border: none;
    font-family: inherit;
    text-align: left;
  }

  .interactive {
    cursor: pointer;
  }

  .glyph {
    display: flex;
    flex: none;
    color: var(--color-icon-standard-base);
  }

  .labels {
    display: flex;
    flex-direction: column;
    /* Raw token gaps: row text keeps its natural line boxes, since these
       numbers are measured against untrimmed boxes on iOS. */
    gap: var(--spacing-n4);
    flex: 1;
    min-width: 0;
  }

  .title,
  .description,
  .value {
    text-box: normal;
  }

  .title {
    color: var(--color-text-standard-base);
  }

  .description,
  .value {
    color: var(--color-text-standard-muted);
  }

  /*
   * The value yields to the title: it truncates rather than pushing it, and
   * keeps more air than the row's gap so a long value never reads as a
   * continuation of the title.
   */
  .value {
    flex: 0 1 auto;
    min-width: 0;
    margin-left: var(--spacing-n8);
    text-align: right;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .accessory {
    display: flex;
    flex: none;
    color: var(--color-text-standard-muted);
  }

  /* One asset, two directions: the chevron points the way in. */
  .chevron {
    transform: rotate(-90deg);
  }
</style>
