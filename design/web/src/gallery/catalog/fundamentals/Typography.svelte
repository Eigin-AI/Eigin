<script lang="ts">
  import { typographyStyles, type TypographyStyle } from "@lib";

  /** Family groups in sans → serif → mono order. */
  const groups = $derived.by(() => {
    const meta: { family: TypographyStyle["family"]; title: string }[] = [
      { family: "display", title: "Sans" },
      { family: "ui", title: "Serif" },
      { family: "mono", title: "Mono" },
    ];
    return meta
      .map(({ family, title }) => ({
        title,
        styles: typographyStyles
          .filter((style) => style.family === family)
          .sort((a, b) => b.fontSize - a.fontSize),
      }))
      .filter((group) => group.styles.length > 0);
  });

  const SPECIMEN_TEXT = "The quick brown fox jumps over the lazy dog";
</script>

<div class="doc">
  {#each groups as group (group.title)}
    <h2 class="t-titleM">{group.title}</h2>
    <div class="specimen">
      {#each group.styles as style (style.name)}
        <div class="row">
          <span class="sample t-{style.name}">{SPECIMEN_TEXT}</span>
          <span class="meta">{style.name} · {style.fontSize}/{style.lineHeight}</span>
        </div>
      {/each}
    </div>
  {/each}
</div>

<style>
  /* A specimen sheet: the type leads, its name sits quietly underneath. */
  .specimen {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n48);
  }

  .row {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n8);
  }

  /* Untrimmed here, so tight line heights don't run the ink into the label. */
  .sample {
    text-box: normal;
  }

  .meta {
    color: var(--color-text-standard-muted);
    font-family: var(--font-mono);
    font-size: 11px;
    line-height: 1.5;
  }
</style>
