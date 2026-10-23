<script lang="ts">
  import { Button, ContentGroup, Row, SegmentedControl, Sheet, Switch } from "@lib";
  let { open = $bindable(false), logging = true }: { open?: boolean; logging?: boolean } = $props();
  let kind = $state("bug");
  let message = $state("");
  let includeLog = $state(false);
  let reviewing = $state(false);
  let status = $state("");
</script>

<Sheet
  bind:open
  title={reviewing ? "Review & send" : "Send feedback"}
  description={reviewing
    ? "Preview your report before opening your mail app."
    : "There’s no tracking in Eigin, so we really appreciate hearing from you. We read every message."}
  onDismiss={() => {
    reviewing = false;
    status = "";
  }}
>
  {#snippet primary()}
    <div class="form">
      {#if reviewing}
        <ContentGroup label="Your report"
          ><Row
            title={kind === "bug"
              ? "Bug report"
              : kind === "feature"
                ? "Feature request"
                : "General feedback"}
            description={message}
            accessory="none"
          /><Row
            title="Log file"
            value={logging && includeLog ? "Included" : "Not included"}
            accessory="none"
          /></ContentGroup
        >
        <Button label="Edit report" variant="secondary" onclick={() => (reviewing = false)} />
        <Button
          label="Send"
          onclick={() => (status = "Preview only — no email was sent and no logs were attached.")}
        />
        {#if status}<p class="t-note" role="status">{status}</p>{/if}
      {:else}
        <SegmentedControl
          segments={[
            { value: "bug", label: "Bug" },
            { value: "feature", label: "Feature" },
            { value: "general", label: "General" },
          ]}
          selection={kind}
          onSelect={(value) => (kind = value)}
        />
        <textarea
          class="t-note"
          aria-label="Feedback message"
          placeholder="What’s on your mind?"
          bind:value={message}
        ></textarea>
        {#if logging}<ContentGroup
            ><Row title="Include log file" accessory="none"
              >{#snippet trailing()}<Switch
                  label="Include log file"
                  isOn={includeLog}
                  onclick={() => (includeLog = !includeLog)}
                />{/snippet}</Row
            ></ContentGroup
          >{/if}
        <Button label="Continue" disabled={!message.trim()} onclick={() => (reviewing = true)} />
      {/if}
    </div>
  {/snippet}
</Sheet>

<style>
  .form {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
    padding: 0 var(--spacing-n16);
  }
  textarea {
    box-sizing: border-box;
    width: 100%;
    min-height: 200px;
    border: none;
    border-radius: var(--radius-card);
    padding: var(--spacing-n24);
    background: var(--color-surface-standard-alternative);
    color: var(--color-text-standard-base);
    resize: vertical;
  }
</style>
