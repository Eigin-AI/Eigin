<script lang="ts">
  import { DataCard, Icon, Sheet } from "@lib";
  import type { Json } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* What a provider actually hands back: a JSON envelope, or a line of prose
     from something that never read the spec. */
  const cases = ["JSON", "Plain text"] as const;
  let chosen = $state<(typeof cases)[number]>("JSON");

  const errors = {
    JSON: {
      title: "Out of credits",
      suggestion:
        "Your provider may require updated billing. Check your provider's dashboard and try again.",
      raw: `{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."},"request_id":"req_011Cbw2joumA3D193gBuVKbk"}`,
    },
    "Plain text": {
      title: "Request failed",
      suggestion: "Your provider returned an error. Tap for details.",
      raw: "invalid json",
    },
  };

  const error = $derived(errors[chosen]);

  /* A provider that answers in prose has no document to read out; its whole
     response is the one fact there is. */
  const payload = $derived.by<Json>(() => {
    try {
      const parsed: Json = JSON.parse(error.raw);
      return typeof parsed === "object" && parsed !== null ? parsed : { response: error.raw };
    } catch {
      return { response: error.raw };
    }
  });

  let copied = $state(false);
  let timer: ReturnType<typeof setTimeout>;

  function copy() {
    navigator.clipboard?.writeText(error.raw);
    clearTimeout(timer);
    copied = true;
    timer = setTimeout(() => (copied = false), 1600);
  }

  useStageControls(() => controls);
</script>

{#snippet controls()}
  <OptionSelector options={[...cases]} bind:value={chosen} />
{/snippet}

<!--
  What went wrong, as far as anyone can tell. The header carries the plain
  reading and what to do about it; the body is the provider's own response,
  read out in full. There is no raw view to reveal because nothing is hidden —
  what the payload said is on screen, and copying it is for taking elsewhere.
-->
<Sheet bind:open title={error.title} description={error.suggestion}>
  {#snippet primary()}
    <div class="detail">
      <DataCard value={payload}>
        {#snippet footnote()}
          <button class="t-tag copy" type="button" onclick={copy}>
            <Icon name={copied ? "functional/check" : "functional/copy"} size={12} />
            <span>{copied ? "Copied" : "Copy raw error"}</span>
          </button>
        {/snippet}
      </DataCard>
    </div>
  {/snippet}
</Sheet>

<style>
  .detail {
    padding: 0 var(--spacing-n16);
  }

  /* Quiet as the small print it stands beside, but set in the display face:
     it is a thing to press, not a sentence to read. */
  .copy {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-n8);
    padding: 0;
    border: none;
    background: transparent;
    color: inherit;
    cursor: pointer;
  }
</style>
