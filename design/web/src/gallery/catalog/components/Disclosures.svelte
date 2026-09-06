<script lang="ts">
  import { Disclosure, OptionPicker, CardSurface } from "@lib";
  import type { Option } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let variant = $state("card");

  const voiceOptions: Option[] = [
    { value: "", label: "System default" },
    { value: "samantha", label: "Samantha", detail: "American" },
    { value: "daniel", label: "Daniel", detail: "British" },
    { value: "karen", label: "Karen", detail: "Australian" },
  ];
  let voice = $state("samantha");
</script>

<div class="doc">
  <h2 class="t-titleM">Disclosure</h2>
  <div class="controls">
    <OptionSelector options={["card", "open"]} bind:value={variant} />
  </div>
  <div class="specimen">
    <div class="sizer">
      {#if variant === "card"}
        <div class="stack">
          <Disclosure title="AI model" description="Llama 3 · lokal">
            <p class="body">
              Choose which model answers you. Local models keep everything on device.
            </p>
          </Disclosure>
          <Disclosure title="Sprog & region" description="Dansk" initiallyExpanded>
            <p class="body">Content is a slot, so a disclosure makes no assumptions.</p>
          </Disclosure>
        </div>
      {:else}
        <!-- The open variant embeds in a CardSurface without doubling up. -->
        <CardSurface padding={0}>
          <Disclosure title="Embedded row 1" variant="open">
            <p class="body">First row content.</p>
          </Disclosure>
          <div class="row-divider"></div>
          <Disclosure title="Embedded row 2" variant="open">
            <p class="body">Second row content.</p>
          </Disclosure>
        </CardSurface>
      {/if}
    </div>
  </div>

  <h2 class="t-titleM">Option picker</h2>
  <div class="specimen">
    <div class="sizer">
      <OptionPicker
        title="Voice"
        options={voiceOptions}
        selection={voice}
        onSelect={(value) => (voice = value)}
      />
    </div>
  </div>
</div>

<style>
  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
  }

  .specimen {
    padding: var(--spacing-n24);
    margin-bottom: var(--spacing-n40);
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-base);
    display: flex;
    justify-content: center;
  }

  .sizer {
    width: 100%;
    max-width: 420px;
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
  }

  .body {
    margin: 0;
    color: var(--color-text-standard-base);
    font-size: 18px;
    line-height: 20.8px;
  }

  .row-divider {
    height: 1px;
    margin: 0 var(--spacing-n24);
    background: var(--color-input-standard-inactive);
  }
</style>
