<script lang="ts">
  import { enhance } from "$app/forms";
  import { untrack } from "svelte";
  import { Button, LinkButton, TextInput } from "@eigin/ui";
  import SpecPreview from "#lib/SpecPreview.svelte";
  import type { PageProps } from "./$types";
  let { data, form }: PageProps = $props();
  let markdown = $state(untrack(() => data.submission?.markdown ?? ""));
  let filename = $state(untrack(() => data.submission?.filename ?? ""));
  let email = $state(untrack(() => data.submission?.email ?? ""));
  let author = $state(
    untrack(() => data.submission?.author ?? data.user?.name ?? ""),
  );
  let authorEmail = $state(
    untrack(() => data.submission?.authorEmail ?? data.user?.authorEmail ?? ""),
  );
  let uploadError = $state("");
  let reading = $state(false);
  let saving = $state(false);
  let fileInput = $state<HTMLInputElement>();
  let sequence = 0;
  $effect(() => {
    const saved = data.submission;
    markdown = saved?.markdown ?? "";
    filename = saved?.filename ?? "";
    email = saved?.email ?? "";
    author = saved?.author ?? data.user?.name ?? "";
    authorEmail = saved?.authorEmail ?? data.user?.authorEmail ?? "";
  });
  async function upload(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    const version = ++sequence;
    uploadError = "";
    if (!file) return;
    reading = true;
    try {
      if (!file.name.toLowerCase().endsWith(".md") || file.size > 256 * 1024)
        throw new Error("Choose a Markdown (.md) file no larger than 256 KiB.");
      const text = new TextDecoder("utf-8", { fatal: true }).decode(
        await file.arrayBuffer(),
      );
      if (version !== sequence) return;
      if (!text.trim() || text.includes("\0"))
        throw new Error(
          "Choose a nonempty Markdown file without null characters.",
        );
      markdown = text;
      filename = file.name;
    } catch (e) {
      if (version === sequence) {
        uploadError =
          e instanceof TypeError
            ? "Choose a valid UTF-8 Markdown file."
            : (e as Error).message;
        input.value = "";
      }
    } finally {
      if (version === sequence) reading = false;
    }
  }
</script>

<svelte:head><title>Your submission · Eigin</title></svelte:head>
<section class="container section">
  <a href="/calls/{data.call.slug}">Back to the call</a>
  <div class="page-intro">
    <h1 class="t-display page-title">Your submission</h1>
    <p class="t-standfirstLarge intro">{data.call.title}</p>
  </div>
  {#if data.submission && !data.editing}
    <div class="submission-layout spaced">
      <div class="stack">
        <div class="receipt stack" role="status">
          <p class="t-miniLabel eyebrow">Submission received</p>
          <h2 class="t-titleM">Your spec is here.</h2>
          <p class="t-body">
            {data.closed
              ? "The call is closed. Your saved spec remains available."
              : "You can update your file and details until the deadline."}
          </p>
          <a href="/calls/{data.call.slug}/submission/download"
            >Download your spec</a
          >
        </div>
        <dl class="credit-summary">
          <div>
            <dt class="t-miniLabel">Contact</dt>
            <dd>{data.submission.email}</dd>
          </div>
          <div>
            <dt class="t-miniLabel">Author credit</dt>
            <dd>{data.submission.author}<br />{data.submission.authorEmail}</dd>
          </div>
        </dl>
        <div class="actions">
          {#if !data.closed}<LinkButton
              href="?edit=1"
              label="Edit your spec"
              variant="outline"
            />{/if}
        </div>
        <aside class="submission-support stack" aria-label="Support Eigin">
          <p class="t-body support-invitation">
            <span aria-hidden="true">⭐</span>
            <strong>Help others discover Eigin by starring the project.</strong>
          </p>
          <div class="actions">
            <a
              href="https://github.com/Eigin-AI/Eigin"
              target="_blank"
              rel="noopener">Star on GitHub</a
            >
            <a
              href="https://code.eigin.ai/dev/eigin"
              target="_blank"
              rel="noopener">Star on GitLab</a
            >
          </div>
        </aside>
      </div>
      <SpecPreview markdown={data.submission.markdown} />
    </div>
  {:else if data.closed}
    <p class="t-standfirst spaced">Submissions are closed.</p>
    {#if data.submission}<a href="/calls/{data.call.slug}/submission"
        >Back to receipt</a
      >{/if}
  {:else}
    <form
      method="POST"
      enctype="multipart/form-data"
      class="submission-layout spaced"
      use:enhance={() => {
        saving = true;
        return async ({ update }) => {
          try {
            await update();
          } finally {
            saving = false;
          }
        };
      }}
    >
      <input
        type="hidden"
        name="expectedRevision"
        value={data.submission?.id ?? ""}
      />
      <input type="hidden" name="claVersion" value={data.claVersion} />
      <input type="hidden" name="termsVersion" value={data.termsVersion} />
      <input type="hidden" name="claHash" value={data.claHash} />
      <input type="hidden" name="termsHash" value={data.termsHash} />
      <input type="hidden" name="email" value={email} />
      <input type="hidden" name="author" value={author} />
      <input type="hidden" name="authorEmail" value={authorEmail} />
      <div class="stack submission-fields">
        <section class="form-section stack">
          <h2 class="t-titleS">
            {data.submission ? "Update your spec" : "Upload your spec"}
          </h2>
          <p class="t-body">Private to you and the review team.</p>
          <label class="t-miniLabel" for="spec-file">Markdown file (.md)</label>
          <div>
            <Button
              label="Choose file"
              variant="outline"
              type="button"
              disabled={!fileInput}
              onclick={() => fileInput?.click()}
            />
          </div>
          <input
            bind:this={fileInput}
            hidden
            id="spec-file"
            name="file"
            type="file"
            accept=".md,text/markdown"
            onchange={upload}
          />
          {#if filename}<p class="t-note">
              Current file: {filename}{data.submission
                ? " · Keep it or choose a replacement."
                : ""}
            </p>{/if}
        </section>
        <section class="form-section stack">
          <h2 class="t-titleS">Contact and credit</h2>
          <TextInput
            label="Contact email"
            type="email"
            required
            bind:value={email}
          />
          <p class="t-note">
            We’ll email the decision here. This address stays private and is not
            independently verified.
          </p>
          <TextInput label="Git author name" required bind:value={author} />
          <TextInput
            label="Git author email"
            type="email"
            required
            bind:value={authorEmail}
          />
          <p class="t-note">
            Author details become public when a spec is published. You can use
            your GitLab private commit email.
          </p>
        </section>
        <section class="form-section stack">
          <h2 class="t-titleS">Agreements</h2>
          <div class="agreement-options">
            <label class="check-row"
              ><input
                name="acceptedCla"
                checked={data.accepted.cla}
                type="checkbox"
                required
              /><span
                >I agree to the <a
                  href="https://docs.eigin.ai/contributing/individual-agreement.html"
                  target="_blank"
                  rel="noopener">Eigin Individual CLA v1.0</a
                >.</span
              ></label
            >
            <label class="check-row"
              ><input
                name="acceptedTerms"
                checked={data.accepted.terms}
                type="checkbox"
                required
              /><span
                >I accept the <a
                  href="/guides/participation-terms"
                  target="_blank"
                  rel="noopener">participation terms</a
                >.</span
              ></label
            >
          </div>
        </section>
        {#if uploadError || form?.message}<p role="alert" class="field-error">
            {uploadError || form?.message}
          </p>{/if}
        <div class="actions" class:equal-actions={!!data.submission}>
          <Button
            label={saving
              ? "Saving…"
              : reading
                ? "Reading file…"
                : data.submission
                  ? "Save changes"
                  : "Submit"}
            size="medium"
            disabled={saving || reading || !!uploadError}
          />
          {#if data.submission}<LinkButton
              href="/calls/{data.call.slug}/submission"
              label="Cancel"
              size="medium"
              variant="outline"
            />{/if}
        </div>
      </div>
      <SpecPreview {markdown} />
    </form>
  {/if}
</section>
