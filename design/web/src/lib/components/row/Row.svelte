<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "../icon/Icon.svelte";
  import Mark from "../status/Mark.svelte";
  import type { IconName } from "../../generated/icons";

  interface Props {
    title: string;
    /** Supporting line under the title. */
    description?: string;
    /** Optional cap for supporting text; full text remains available in details. */
    descriptionLineLimit?: number;
    /** Supporting line with inline markup, such as a link. Wins over `description`. */
    descriptionContent?: Snippet;
    /** Current setting, shown at the trailing edge. Truncates rather than wraps. */
    value?: string;
    /** Leading glyph. */
    icon?: IconName;
    /** Stand-in mark for a row whose subject has no logo: its own initial. */
    letter?: string;
    /** What the row promises: navigation, an external link, adding, removing,
        or nothing. */
    accessory?: "chevron" | "link" | "plus" | "trash" | "none";
    /** How loudly the row speaks. Accent is for the one thing you might be
        hunting for in a settled list; muted defers to somewhere else;
        destructive keeps its red to the glyph. */
    tone?: "standard" | "accent" | "muted" | "destructive";
    /** A control in place of the accessory — a switch, a small button. */
    trailing?: Snippet;
    onclick?: () => void;
  }

  const {
    title,
    description,
    descriptionLineLimit,
    descriptionContent,
    value,
    icon,
    letter,
    accessory = "chevron",
    tone = "standard",
    trailing,
    onclick,
  }: Props = $props();

  const interactive = $derived(Boolean(onclick));
  const showsAccessory = $derived(!trailing && accessory !== "none");

  const accessoryIcon = $derived<IconName>(
    accessory === "link"
      ? "functional/arrow/up_right"
      : accessory === "plus"
        ? "functional/plus"
        : accessory === "trash"
          ? "functional/trash"
          : "functional/chevron/right",
  );
</script>

<!--
  One row of a content group: an optional leading glyph, the title with an
  optional supporting line, an optional value, and a trailing accessory or
  control.

  Adding, removing and deferring are this row in another tone, not components
  of their own: a plus in the accent adds to the group it closes, a muted
  chevron opens the longer version, and a trash with its red kept to the glyph
  takes the connection away. Sharing one implementation is also what keeps
  their metrics honest — as separate components they stood 9px short.

  Web-first: iOS repeats this layout by hand on every settings screen rather
  than sharing a component.
-->
{#snippet contents()}
  {#if icon}
    <span class="glyph"><Icon name={icon} size={24} /></span>
  {:else if letter}
    <!-- Same circle the identity header uses, sized to the glyph slot: a row
         of services keeps one leading column whether or not we ship a logo. -->
    <span class="glyph"><Mark {letter} size={32} /></span>
  {/if}

  <span class="labels">
    <span class="t-titleXS title">{title}</span>
    {#if descriptionContent || description}
      <span
        class="t-tag description"
        class:clamped={descriptionLineLimit !== undefined}
        style:--description-lines={descriptionLineLimit}
      >
        {#if descriptionContent}{@render descriptionContent()}{:else}{description}{/if}
      </span>
    {/if}
  </span>

  {#if value}
    <span class="t-tag value">{value}</span>
  {/if}

  {#if trailing}
    {@render trailing()}
  {:else if showsAccessory}
    <span class="accessory">
      <Icon name={accessoryIcon} size={16} />
    </span>
  {/if}
{/snippet}

<!-- A row that does something is a button; a row that only states something is
     a plain element, so it never sits in the tab order promising an action. -->
{#if interactive}
  <button class="eigin-row interactive {tone}" type="button" {onclick}>
    {@render contents()}
  </button>
{:else}
  <div class="eigin-row {tone}">
    {@render contents()}
  </div>
{/if}

<style>
  .description.clamped {
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: var(--description-lines);
    line-clamp: var(--description-lines);
    overflow: hidden;
    overflow-wrap: anywhere;
  }

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

  /* A fixed box, so a logo and a letter mark start on the same column and the
     titles beside them line up whichever a row happens to have. */
  .glyph {
    display: flex;
    flex: none;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
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

  /* Adding is the one thing in a list of settled rows you might be hunting
     for, so the whole line is allowed to be the thing the eye lands on. */
  .accent .title,
  .accent .accessory {
    color: var(--color-accent);
  }

  /* What it opens is optional: the card above already said what you needed. */
  .muted .title {
    color: var(--color-text-standard-muted);
  }

  /* Never a red label. `text.standard.error` is #FF0004, a pure signal red
     meant for filled buttons and glyphs, and at title weight on a warm page it
     is the only cold, fully saturated thing on screen. Kept to the glyph, the
     same red does its job without shouting. */
  .destructive .accessory {
    color: var(--color-text-standard-error);
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
</style>
