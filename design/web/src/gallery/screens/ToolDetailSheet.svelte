<script lang="ts">
  import { DataCard, Sheet, StatusLine } from "@lib";
  import type { ConnectionState, Json, ToolStatus } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import "@lib/theme/pulse.css";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* The five tool states, plus the case a finished call returns nothing —
     the one the sheet currently answers with silence. */
  const cases = ["Completed", "Empty result", "Executing", "Awaiting", "Denied", "Error"] as const;
  let chosen = $state<(typeof cases)[number]>("Completed");

  const status = $derived<ToolStatus>(
    chosen === "Executing"
      ? "executing"
      : chosen === "Awaiting"
        ? "awaitingPermission"
        : chosen === "Denied"
          ? "denied"
          : chosen === "Error"
            ? "error"
            : "completed",
  );

  /* Status is the same vocabulary a connection uses: a dot and a word. Green
     is done, amber wants something from you, red is a call that did not run,
     and a running call pulses. */
  const dot = $derived<ConnectionState>(
    status === "completed"
      ? "connected"
      : status === "awaitingPermission"
        ? "attention"
        : status === "denied" || status === "error"
          ? "unavailable"
          : "connecting",
  );

  /* What a tool call carries: JSON on the wire, read out as facts here. */
  const input: Json = {
    field: "identity",
    value: "Keeps Friday mornings clear, and says so before the week fills.",
    overwrite: false,
  };

  const result: Json = {
    saved: true,
    revision: 14,
    supersedes: null,
  };

  /*
   * The status carries whatever the sheet is not showing elsewhere. A call
   * that finished with nothing to return says so here rather than in an empty
   * output block, and a failed one leaves the reason to the card below.
   */
  const statusLabel = $derived(
    status === "completed"
      ? chosen === "Completed"
        ? "Completed"
        : "Completed with no output"
      : status === "executing"
        ? "Executing"
        : status === "awaitingPermission"
          ? "Awaiting permission"
          : status === "denied"
            ? "Denied by the user"
            : "Failed",
  );

  /* Only two states have anything to show: a result, or why there is none. */
  const output = $derived<Json | undefined>(
    status === "completed" && chosen === "Completed"
      ? result
      : status === "error"
        ? { error: "Connection timeout after 30s", attempts: 3, retryable: true }
        : undefined,
  );

  useStageControls(() => controls);
</script>

{#snippet controls()}
  <OptionSelector options={[...cases]} bind:value={chosen} />
{/snippet}

<!-- Bound to the card it comments on rather than floating between them. -->
{#snippet statusNote()}
  <span class:eigin-pulse={status === "executing"}>
    <StatusLine state={dot} label={statusLabel} />
  </span>
{/snippet}

<!--
  What the agent actually did, in one call.

  It reads in the order the call happened: what it was asked, what came back,
  and where it got to. The input is always there; the output appears only when
  there is something to show, so a call still running does not carry an empty
  block waiting to be filled.

  The status is the footnote of whichever card is last, so it reads as a
  remark about that card rather than as a line of its own: under the input
  while the call is still going, and under the output once there is one.
-->
<Sheet
  bind:open
  title="Edit core memory"
  description="Changes what the agent remembers about you between conversations."
>
  {#snippet primary()}
    <div class="detail">
      <DataCard label="Input" value={input} footnote={output ? undefined : statusNote} />

      {#if output}
        <DataCard
          label={status === "error" ? "Error" : "Output"}
          value={output}
          footnote={statusNote}
        />
      {/if}
    </div>
  {/snippet}
</Sheet>

<style>
  .detail {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n16);
  }
</style>
