<script lang="ts">
  import Disclosure from "./Disclosure.svelte";
  import Icon from "../icon/Icon.svelte";
  import type { Option } from "./types";

  let {
    title,
    description,
    options,
    selection,
    initiallyExpanded = false,
    onSelect,
  }: {
    title: string;
    /** Defaults to the selected option's label. */
    description?: string;
    options: Option[];
    selection: string;
    /** Forwarded to the disclosure; the picker always starts folded. */
    initiallyExpanded?: boolean;
    onSelect?: (value: string) => void;
  } = $props();

  /* Shows the explicit description, else the selected option's label. */
  const summary = $derived(
    description ?? options.find((option) => option.value === selection)?.label,
  );
</script>

<!--
  A disclosure that folds out a single-select list.
  Reflects `selection` and reports taps, leaving state with the caller.

  A detail reads as part of the label — "Daniel (British)" — in one type, the
  way the app writes it, and sets it apart in `note` at the trailing edge.
-->
<Disclosure {title} description={summary} {initiallyExpanded}>
  <div class="options" role="radiogroup">
    {#each options as option (option.value)}
      <button
        type="button"
        role="radio"
        aria-checked={option.value === selection}
        class="option"
        onclick={() => onSelect?.(option.value)}
      >
        <span class="t-navTab label" class:selected={option.value === selection}>
          {option.detail ? `${option.label} (${option.detail})` : option.label}
        </span>
        <span class="spacer"></span>
        <span class="check" class:visible={option.value === selection}>
          <Icon name="functional/check" size={16} />
        </span>
      </button>
    {/each}
  </div>
</Disclosure>

<style>
  .options {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
  }

  .option {
    display: flex;
    align-items: center;
    /* Trimmed text is shorter than the check glyph, so pin the row height
       to keep selected and unselected rows identical. */
    min-height: 16px;
    gap: var(--spacing-n8);
    width: 100%;
    padding: 0;
    background: transparent;
    border: none;
    font-family: inherit;
    text-align: left;
    cursor: pointer;
  }

  .label {
    color: var(--color-text-standard-muted);
  }

  .label.selected {
    color: var(--color-text-standard-base);
  }

  .spacer {
    flex: 1;
  }

  /* Always present so selecting a row doesn't shift the layout. */
  .check {
    display: inline-flex;
    color: var(--color-text-standard-base);
    visibility: hidden;
  }

  .check.visible {
    visibility: visible;
  }
</style>
