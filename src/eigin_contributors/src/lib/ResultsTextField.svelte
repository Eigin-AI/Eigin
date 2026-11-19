<script lang="ts">
  let {
    name,
    value,
    example,
    limit,
    rows,
  }: {
    name: string;
    value: string;
    example: string;
    limit: number;
    rows: number;
  } = $props();
  const escape = (text: string) =>
    text.replace(
      /[&<>"']/g,
      (character) =>
        (
          ({
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            '"': "&quot;",
            "'": "&#39;",
          }) as Record<string, string>
        )[character]!,
    );
  // Native form values must survive typing while the page hydrates.
  const html = $derived(
    `<textarea id="results-${escape(name)}" name="${escape(name)}" maxlength="${limit}" placeholder="${escape(example)}" rows="${rows}" aria-describedby="hint-${escape(name)}">\n${escape(value)}</textarea>`,
  );
</script>

<div class="results-text-field">{@html html}</div>

<style>
  .results-text-field :global(textarea) {
    width: 100%;
    box-sizing: border-box;
    resize: vertical;
    min-height: 120px;
    padding: var(--spacing-n16);
    border: 0;
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-base);
    color: inherit;
    font: inherit;
    line-height: var(--portal-body-leading);
  }
</style>
