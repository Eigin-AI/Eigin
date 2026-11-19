<script lang="ts">
  import { Button, LinkButton } from "@eigin/ui";
  import ResultsPage from "#lib/ResultsPage.svelte";
  import type { PageProps } from "./$types";
  let { data, form }: PageProps = $props();
  const prepared = $derived(form && "prepared" in form ? form.prepared : null);
  const base = $derived(`/review/calls/${data.call.slug}/selection`);
</script>

<div data-sveltekit-reload>
  {#if form && "message" in form}<p role="alert" class="t-body spaced">
      {form.message}
    </p>{/if}
  {#if prepared}
    <p class="t-body">
      This results page and both funded specs will be readable without signing
      in. Other submissions stay private.
    </p>
    <ResultsPage
      title={prepared.preview.title}
      summary={prepared.preview}
      copy={prepared.preview.copy}
      links={{ selected: base + "/selected", runnerUp: base + "/runner-up" }}
    />
    <form method="POST" action="?/publish" class="stack spaced">
      <input
        type="hidden"
        name="confirmationToken"
        value={prepared.confirmationToken}
      />
      <label class="t-body" for="publication-text"
        >Type <strong>publish</strong> to publish the results</label
      >
      <input
        id="publication-text"
        name="confirmationText"
        required
        autocomplete="off"
        spellcheck="false"
        maxlength="64"
      />
      <p class="t-note">Git publication, emails, and payments remain manual.</p>
      <div class="actions decision-actions">
        <button
          type="submit"
          formaction="?/cancel"
          formnovalidate
          class="eigin-btn outline medium"
          ><span class="t-button">Cancel</span></button
        >
        <Button type="submit" label="Publish results" size="medium" />
      </div>
    </form>
  {:else}
    <form method="POST" action="?/prepare" class="actions spaced">
      <input type="hidden" name="intent" value="preview-publication" />
      <LinkButton
        href={base}
        label="Back to selection"
        variant="outline"
        size="medium"
      />
      <Button type="submit" label="Preview publication" size="medium" />
    </form>
  {/if}
</div>

<style>
  #publication-text {
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
</style>
