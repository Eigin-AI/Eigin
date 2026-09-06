<script lang="ts">
  import { Switch, SegmentedControl } from "@lib";
  import type { Segment } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  const states = ["enabled", "disabled"] as const;

  let switchOn = $state(true);
  let switchState = $state<(typeof states)[number]>("enabled");

  const segments: Segment[] = [
    { value: "reactive", label: "Reactive" },
    { value: "balanced", label: "Balanced" },
    { value: "proactive", label: "Proactive" },
  ];
  let selection = $state("reactive");
  let segmentedState = $state<(typeof states)[number]>("enabled");
  let segmentCount = $state("three");
</script>

<div class="doc">
  <h2 class="t-titleM">Switch</h2>
  <div class="controls">
    <OptionSelector options={states} bind:value={switchState} />
  </div>
  <div class="specimen">
    <Switch
      isOn={switchOn}
      label="Example switch"
      disabled={switchState === "disabled"}
      onclick={() => (switchOn = !switchOn)}
    />
  </div>

  <h2 class="t-titleM">Segmented control</h2>
  <div class="controls">
    <OptionSelector options={["two", "three"]} bind:value={segmentCount} />
    <OptionSelector options={states} bind:value={segmentedState} />
  </div>
  <div class="specimen">
    <div class="sizer">
      <SegmentedControl
        segments={segmentCount === "two" ? segments.slice(0, 2) : segments}
        {selection}
        disabled={segmentedState === "disabled"}
        onSelect={(value) => (selection = value)}
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

  /* Segmented control fills its container, so give it the phone column. */
  .sizer {
    width: 100%;
    max-width: 345px;
  }
</style>
