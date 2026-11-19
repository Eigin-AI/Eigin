<script lang="ts">
  import { onMount, untrack } from "svelte";
  import { Button, LinkButton } from "@eigin/ui";
  import { page } from "$app/state";
  import ResultsPage from "#lib/ResultsPage.svelte";
  import ResultsEditor from "#lib/ResultsEditor.svelte";
  import SelectionSummary from "#lib/SelectionSummary.svelte";
  import type { PageProps } from "./$types";
  let { data, form }: PageProps = $props();
  let enhanced = $state(false);
  onMount(() => {
    enhanced = true;
  });
  let selected = $state(untrack(() => data.choices.selected));
  let runnerUp = $state(untrack(() => data.choices.runnerUp));
  const base = $derived(`/review/calls/${data.call.slug}/selection`);
  const confirmation = $derived(
    form && "confirmation" in form ? form.confirmation : null,
  );
  const message = $derived(
    form && "message" in form ? form.message : data.message,
  );
  const editing = $derived(form && "editing" in form ? form.editing : null);
  const editorSummary = $derived(editing?.summary ?? data.summary);
</script>

<div data-sveltekit-reload data-enhanced={enhanced}>
  {#if message}<p role="alert" class="t-body selection-error">{message}</p>{/if}
  {#if data.recorded}
    {#if page.url.searchParams.has("existing")}<p
        role="status"
        class="t-body spaced"
      >
        A selection was already recorded. This request did not record another
        decision.
      </p>{/if}
    {#if data.publicationStatus}
      <LinkButton
        href={`/calls/${data.call.slug}`}
        label="View public results"
        variant="outline"
        size="medium"
      />
    {:else}
      <p class="t-body">These results are private.</p>
      {#if data.canPublish && data.recorded.resultsCopy}
        <form method="POST" action={base + "/publish?/prepare"} class="spaced">
          <input type="hidden" name="intent" value="preview-publication" />
          <Button type="submit" label="Publish results" size="medium" />
        </form>
      {/if}
    {/if}
    <hr class="preview-divider" />
    {#if data.recorded.resultsCopy}
      <ResultsPage
        title={data.call.title}
        summary={data.recorded}
        copy={data.recorded.resultsCopy}
        links={{ selected: base + "/selected", runnerUp: base + "/runner-up" }}
      />
    {:else}<SelectionSummary summary={data.recorded} recorded />{/if}
    <p class="t-note">
      Confirmed by GitLab user {data.recorded.confirmedByGitlabId} · {new Date(
        data.recorded.confirmedAt,
      ).toISOString()}
    </p>
  {:else if confirmation}
    <p class="t-body">
      This is how the completed call will read. Check the copy and both
      recipients before confirming the selection.
    </p>
    <hr class="preview-divider" />
    <ResultsPage
      title={data.call.title}
      summary={confirmation.summary}
      copy={confirmation.copy}
      links={{
        selected: `/review/calls/${data.call.slug}/submissions/${confirmation.summary.selected.submissionId}`,
        runnerUp: `/review/calls/${data.call.slug}/submissions/${confirmation.summary.runnerUp.submissionId}`,
      }}
    />
    <h2 class="t-titleM spaced">Confirm selection</h2>
    <form method="POST" action="?/confirm" class="stack spaced">
      <input
        type="hidden"
        name="confirmationToken"
        value={confirmation.confirmationToken}
      />
      <label class="t-body" for="confirmation-text"
        >Type <strong>confirm</strong> to confirm</label
      >
      <input
        id="confirmation-text"
        name="confirmationText"
        required
        autocomplete="off"
        spellcheck="false"
        maxlength="64"
      />
      <div class="actions decision-actions">
        <button
          type="submit"
          formaction="?/cancel"
          formnovalidate
          class="eigin-btn outline medium"
          ><span class="t-button">Edit results</span></button
        >
        <Button type="submit" label="Confirm selection" size="medium" />
      </div>
    </form>
  {:else if editorSummary}
    {#if page.url.searchParams.has("saved") && !message}<p
        role="status"
        class="t-body selection-error"
      >
        Draft saved.
      </p>{/if}
    {#if editing}<LinkButton
        href={base + "?step=write"}
        label="Reload saved draft"
        variant="outline"
        size="small"
      />{/if}
    <ResultsEditor
      summary={editorSummary}
      copy={editing?.copy ?? data.copy}
      version={editing?.version ?? data.draftVersion}
      choices={editing?.choices ?? data.choices}
    />
  {:else if data.call.status !== "closed"}
    <h2 class="t-titleM">Selection opens after the deadline</h2>
    <p class="t-body spaced">
      You can read submissions now. Recipients can be selected once the call
      closes.
    </p>
  {:else}
    <p class="t-body">Choose one selected spec and a different runner-up.</p>
    <form method="GET" action={base} class="stack spaced">
      <input type="hidden" name="selected" value={data.choices.selected} />
      <input type="hidden" name="runnerUp" value={data.choices.runnerUp} />
      <div class="selection-list">
        {#each data.entries as entry (entry.id)}
          <fieldset aria-label={entry.author + " · " + entry.title}>
            <div class="recipient-meta">
              <p class="t-titleXS">{entry.author}</p>
              <p class="t-body">{entry.title}</p>
            </div>
            <div class="choices t-body">
              <label
                ><input
                  type="radio"
                  name="selected"
                  value={`${entry.id}:${entry.revisionId}`}
                  onchange={() => {
                    if (runnerUp === `${entry.id}:${entry.revisionId}`)
                      runnerUp = "";
                  }}
                  bind:group={selected}
                /> Selected spec</label
              >
              <label
                ><input
                  type="radio"
                  name="runnerUp"
                  value={`${entry.id}:${entry.revisionId}`}
                  onchange={() => {
                    if (selected === `${entry.id}:${entry.revisionId}`)
                      selected = "";
                  }}
                  bind:group={runnerUp}
                /> Runner-up spec</label
              >
              <a
                href={`/review/calls/${data.call.slug}/submissions/${entry.id}`}
                target="_blank"
                rel="noopener"
                class="read-spec"
                aria-label={`Read spec by ${entry.author}`}>Read spec</a
              >
            </div>
          </fieldset>
        {:else}<p class="t-body">No submissions on this page.</p>{/each}
      </div>
      <nav class="actions decision-actions" aria-label="Recipient pages">
        {#if data.page > 1}<button
            type="submit"
            name="page"
            value={data.page - 1}
            class="page-choice t-miniLabel">Previous</button
          >{/if}
        {#if data.hasNext}<button
            type="submit"
            name="page"
            value={data.page + 1}
            class="page-choice t-miniLabel">Next</button
          >{/if}
      </nav>
      <div class="actions decision-actions">
        <LinkButton
          href={data.hasDraft
            ? base + "?step=write"
            : `/review/calls/${data.call.slug}`}
          label="Cancel"
          variant="outline"
          size="medium"
        />
        <button
          type="submit"
          name="step"
          value="write"
          class="eigin-btn primary medium"
          ><span class="t-button">Write the results</span></button
        >
      </div>
    </form>
  {/if}
</div>

<style>
  .decision-actions :global(.eigin-btn) {
    width: auto;
  }
  .preview-divider {
    border: 0;
    border-top: 1px solid var(--color-border-standard-base);
    margin-block: var(--spacing-n32);
  }
  .selection-list {
    display: grid;
    gap: var(--spacing-n8);
    max-height: 65svh;
    overflow-y: auto;
    padding: var(--spacing-n4);
  }
  fieldset {
    min-width: 0;
    margin: 0;
    border: 0;
    border-radius: var(--radius-card);
    padding: var(--spacing-n16);
    background: var(--color-surface-standard-base);
  }
  .recipient-meta {
    display: grid;
    gap: var(--spacing-n8);
    overflow-wrap: anywhere;
  }
  .choices {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: var(--spacing-n16);
    margin-top: var(--spacing-n12);
  }
  .choices label,
  .read-spec {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-n8);
    min-height: 36px;
  }
  input[type="radio"] {
    width: 20px;
    height: 20px;
    flex-shrink: 0;
    margin: 0;
  }
  #confirmation-text {
    width: 100%;
    max-width: 36rem;
    box-sizing: border-box;
    padding-inline: var(--sizing-input-px-left);
    min-height: var(--sizing-input-height);
    border: 0;
    border-radius: var(--radius-full);
    color: inherit;
    background: var(--color-input-standard-active);
    font: inherit;
  }
  .selection-error {
    margin-bottom: var(--spacing-n24);
  }
  .page-choice {
    background: transparent;
    color: inherit;
    border: 0;
    text-decoration: underline;
    cursor: pointer;
  }
  @media (min-width: 960px) {
    fieldset {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      align-items: center;
      gap: var(--spacing-n24);
    }
    .choices {
      margin-top: 0;
    }
  }
  @media (max-width: 600px) {
    .decision-actions :global(.eigin-btn) {
      width: 100%;
    }
  }
</style>
