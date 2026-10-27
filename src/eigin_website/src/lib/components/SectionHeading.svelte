<script lang="ts">
  import { Icon } from "@eigin/ui";

  /** A section heading with a decorative arrow on wide layouts. */
  let {
    title,
    id,
    class: className = "",
    headingClass = "",
  }: {
    title: string;
    id?: string;
    class?: string;
    headingClass?: string;
  } = $props();
</script>

<div class="section-heading {className}">
  <h2 class="t-titleM {headingClass}" {id}>{title}</h2>
  <span class="section-heading-icon" aria-hidden="true">
    <Icon name="functional/arrow/right" size={20} />
  </span>
</div>

<style>
  .section-heading {
    display: grid;
    grid-template-columns: minmax(0, calc(var(--spacing-n128) + var(--spacing-n64))) max-content;
    align-items: center;
    gap: var(--spacing-n16);
    min-width: 0;
  }

  .section-heading-icon {
    display: inline-flex;
  }

  @media (max-width: 1199px) {
    .section-heading {
      grid-template-columns: minmax(0, 1fr);
    }

    .section-heading-icon {
      display: none;
    }
  }
</style>
