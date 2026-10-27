<script lang="ts">
  import { Switch, SegmentedControl, FloatingPicker, PickerRow } from "@lib";
  import type { Segment } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  const languages = [
    { value: "en", label: "English", detail: undefined, emoji: undefined },
    { value: "da", label: "Dansk", detail: undefined, emoji: undefined },
  ];
  const workspaces = [
    { value: "personal", label: "Personal", detail: "Your own agent and memory", emoji: "🌿" },
    { value: "team", label: "Team", detail: "A shared context for your team", emoji: "🐝" },
  ];
  let pickerContent = $state("Languages");
  let language = $state("en");
  let workspace = $state("personal");
  const pickerOptions = $derived(pickerContent === "Languages" ? languages : workspaces);
  const pickerValue = $derived(pickerContent === "Languages" ? language : workspace);
  const currentOption = $derived(pickerOptions.find((option) => option.value === pickerValue));

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
  <h2 class="t-titleM">Floating picker</h2>
  <div class="controls">
    <OptionSelector options={["Languages", "Detailed rows"]} bind:value={pickerContent} />
  </div>
  <div class="specimen">
    <FloatingPicker
      label="Floating picker: {currentOption?.label}"
      rowGap={pickerContent === "Detailed rows" ? 24 : 16}
    >
      {#snippet trigger()}<span class="t-buttonSmall"
          >{pickerContent === "Languages" ? pickerValue.toUpperCase() : currentOption?.label}</span
        >{/snippet}
      {#snippet children(dismiss)}
        {#each pickerOptions as option (option.value)}
          <PickerRow
            selected={pickerValue === option.value}
            onclick={() => {
              dismiss();
              if (pickerContent === "Languages") language = option.value;
              else workspace = option.value;
            }}
          >
            <span class="picker-row-content">
              {#if option.emoji}<span class="space-emoji" aria-hidden="true">{option.emoji}</span
                >{/if}
              <span class="space-labels">
                <span class={option.detail ? "t-titleXS" : "t-navTab"}>{option.label}</span>
                {#if option.detail}<span class="t-note space-description">{option.detail}</span
                  >{/if}
              </span>
            </span>
          </PickerRow>
        {/each}
      {/snippet}
    </FloatingPicker>
  </div>
</div>

<style>
  .picker-row-content {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
  }
  .space-emoji {
    font-size: 28px;
    line-height: 1;
    flex-shrink: 0;
  }
  .space-labels {
    display: grid;
    gap: var(--spacing-n8);
    min-width: 0;
  }
  .space-description {
    color: var(--color-text-standard-muted);
  }
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
