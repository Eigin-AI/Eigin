<script lang="ts">
  import { Button, LinkButton } from "@eigin/ui";
  import ResultsTextField from "./ResultsTextField.svelte";
  import SelectionSummary from "./SelectionSummary.svelte";
  import { resultsFields, type ResultsCopy } from "./results-copy.ts";
  import type { SelectionSummary as Summary } from "./server/selection.ts";
  let {
    summary,
    copy,
    version,
    choices,
  }: {
    summary: Summary;
    copy: ResultsCopy;
    version: string;
    choices: { selected: string; runnerUp: string };
  } = $props();
</script>

<p class="t-body">Tell contributors what we valued and what we learned.</p>
<SelectionSummary {summary} />
<form method="POST" action="?/preview" class="stack results-editor">
  <input type="hidden" name="selected" value={choices.selected} />
  <input type="hidden" name="runnerUp" value={choices.runnerUp} />
  <input type="hidden" name="draftVersion" value={version} />
  {#each resultsFields as field}
    <div class="stack editor-field">
      <label for={`results-${field.key}`} class="t-titleXS">{field.label}</label
      >
      <p id={`hint-${field.key}`} class="t-body">{field.hint}</p>
      <ResultsTextField
        name={field.key}
        value={copy[field.key]}
        example={field.example}
        limit={field.limit}
        rows={field.key === "learned" ? 7 : 4}
      />
    </div>
  {/each}
  <p class="t-note">Use plain text.</p>
  <div class="actions editor-actions">
    <LinkButton
      href={`/review/calls/${summary.callSlug}/selection?step=choose&${new URLSearchParams(choices)}`}
      label="Change recipients"
      variant="outline"
      size="medium"
    />
    <button
      type="submit"
      formaction="?/saveDraft"
      class="eigin-btn outline medium"
      ><span class="t-button">Save draft</span></button
    >
    <Button type="submit" label="Preview results" size="medium" />
  </div>
</form>

<style>
  .results-editor {
    max-width: 880px;
  }
  .editor-field {
    gap: var(--spacing-n12);
  }
  .editor-actions :global(.eigin-btn) {
    width: auto;
  }
  @media (max-width: 600px) {
    .editor-actions :global(.eigin-btn) {
      width: 100%;
    }
  }
</style>
