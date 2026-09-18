<script lang="ts">
  import { CodeBlock, DataCard, Icon } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { payloads } from "./dataPayloads";

  let chosen = $state(payloads[0].label);
  const payload = $derived(payloads.find((entry) => entry.label === chosen) ?? payloads[0]);

  let copied = $state(false);
  let timer: ReturnType<typeof setTimeout>;

  function copy() {
    navigator.clipboard?.writeText(JSON.stringify(payload.value, null, 2));
    clearTimeout(timer);
    copied = true;
    timer = setTimeout(() => (copied = false), 1600);
  }
</script>

<div class="doc">
  <h2 class="t-titleM">Data card</h2>
  <p class="lede t-description">
    Semi-structured data shown as a datasheet. Built for machine-generated data: tool inputs,
    outputs, error messages. Usable for any semi-structured data, JSON typically, that a screen has
    to show.
  </p>

  <h3 class="t-titleXS section">Approach</h3>
  <ul class="rules t-description">
    <li>Every fact is a label and a value. A flat object produces a list of facts.</li>
    <li>A row with data underneath expands. Chevrons and lines mark what is nested.</li>
    <li>Nested data reads like the top level, indented.</li>
    <li>A list of matching items becomes a table, a column per field.</li>
    <li>A list of plain values becomes a single row.</li>
    <li>Long lists show the start and expand to show the rest.</li>
  </ul>
  <p class="lede t-description tail-note">
    It is a best effort. This data is machine generated and was never meant for a screen, and its
    shape cannot be designed for ahead of time. So the card renders everything it is given, for
    transparency, and does what it can with the shape it gets.
  </p>

  <div class="controls">
    <OptionSelector options={payloads.map((entry) => entry.label)} bind:value={chosen} />
  </div>
  <p class="t-note about">{payload.about}</p>

  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="page">
        <DataCard value={payload.value} label="Response">
          {#snippet footnote()}
            <button class="t-tag copy" type="button" onclick={copy}>
              <Icon name={copied ? "functional/check" : "functional/copy"} size={12} />
              <span>{copied ? "Copied" : "Copy raw"}</span>
            </button>
          {/snippet}
        </DataCard>
      </div>
    </DeviceFrame>
  </div>

  <h3 class="t-titleXS section">The payload</h3>
  <div class="raw">
    <CodeBlock code={JSON.stringify(payload.value, null, 2)} language="json" />
  </div>
</div>

<style>
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  .section {
    margin: var(--spacing-n40) 0 var(--spacing-n12);
  }

  .rules {
    max-width: 62ch;
    margin: 0;
    padding-left: var(--spacing-n20);
    color: var(--color-text-standard-muted);
  }

  .rules li {
    margin-bottom: var(--spacing-n8);
  }

  .tail-note {
    margin-top: var(--spacing-n24);
  }

  .controls {
    display: flex;
    align-items: flex-start;
    margin: var(--spacing-n32) 0 var(--spacing-n8);
  }

  .about {
    max-width: 62ch;
    margin: 0 0 var(--spacing-n24);
    color: var(--color-text-standard-muted);
  }

  .page {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
  }

  .raw {
    max-width: 62ch;
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
