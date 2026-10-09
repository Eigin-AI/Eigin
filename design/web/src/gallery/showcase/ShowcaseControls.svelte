<script lang="ts">
  import { OptionPicker, SegmentedControl } from "@lib";
  import { screenEntries } from "@gallery/screens/index";
  import ConversationEditor from "@gallery/showcase/ConversationEditor.svelte";
  import {
    anchors,
    backgrounds,
    conversationScreen,
    headlineSizes,
    layouts,
    sizes,
    type Anchor,
    type HeadlineSize,
    type Layout,
    type Placement,
    type Shot,
    type Tilt,
  } from "@gallery/showcase/shots";

  let { shot = $bindable(), title }: { shot: Shot; title: string } = $props();

  const building = $derived(shot.screen === conversationScreen);

  const screenOptions = screenEntries
    .filter((candidate) => !candidate.device)
    .map((candidate) => ({ value: candidate.id, label: candidate.title }));

  const segmentsOf = (list: { id: string; label: string }[]) =>
    list.map(({ id, label }) => ({ value: id, label }));

  const tiltAxes: { key: keyof Tilt; label: string }[] = [
    { key: "yaw", label: "Yaw" },
    { key: "pitch", label: "Pitch" },
    { key: "roll", label: "Roll" },
  ];

  const placementAxes: {
    key: keyof Placement;
    label: string;
    min: number;
    max: number;
    step: number;
  }[] = [
    { key: "x", label: "X", min: -50, max: 50, step: 0.5 },
    { key: "y", label: "Y", min: -50, max: 50, step: 0.5 },
    { key: "scale", label: "Size", min: 0.4, max: 1.8, step: 0.01 },
  ];

  const placementLabel = (key: keyof Placement, value: number) =>
    key === "scale" ? `${Math.round(value * 100)}%` : `${value}%`;
</script>

<aside class="panel">
  <h2 class="t-titleS panel-title">{title}</h2>

  {#if building && shot.conversation}
    <section class="panel-section">
      <h3 class="t-miniLabel section-title">Conversation</h3>
      <ConversationEditor bind:turns={shot.conversation} />
    </section>
  {/if}

  <section class="panel-section">
    <h3 class="t-miniLabel section-title">Phone</h3>
    {#if !building}
      <OptionPicker
        title="Screen"
        options={screenOptions}
        selection={shot.screen}
        onSelect={(next) => (shot.screen = next)}
      />
    {/if}
    <div class="field">
      <span class="t-descriptionSmall field-label">Pose</span>
      <SegmentedControl
        segments={segmentsOf(layouts)}
        selection={shot.layout}
        onSelect={(next) => (shot.layout = next as Layout)}
      />
    </div>
    <div class="field">
      <span class="t-descriptionSmall field-label">Screen</span>
      <SegmentedControl
        segments={[
          { value: "light", label: "Light" },
          { value: "dark", label: "Dark" },
        ]}
        selection={shot.scheme}
        onSelect={(next) => (shot.scheme = next as Shot["scheme"])}
      />
    </div>
    {#if shot.layout === "tilt"}
      {#each tiltAxes as axis (axis.key)}
        <label class="field">
          <span class="t-descriptionSmall field-label">{axis.label} {shot.tilt[axis.key]}°</span>
          <input type="range" min="-45" max="45" step="1" bind:value={shot.tilt[axis.key]} />
        </label>
      {/each}
    {/if}
    {#each placementAxes as axis (axis.key)}
      <label class="field">
        <span class="t-descriptionSmall field-label">
          {axis.label}
          {placementLabel(axis.key, shot.placement[axis.key])}
        </span>
        <input
          type="range"
          min={axis.min}
          max={axis.max}
          step={axis.step}
          bind:value={shot.placement[axis.key]}
        />
      </label>
    {/each}
    <label class="field">
      <span class="t-descriptionSmall field-label">Glare {Math.round(shot.glare * 100)}%</span>
      <input type="range" min="0" max="1" step="0.01" bind:value={shot.glare} />
    </label>
    <label class="field">
      <span class="t-descriptionSmall field-label">Light {shot.light.angle}°</span>
      <input type="range" min="-180" max="180" step="1" bind:value={shot.light.angle} />
    </label>
    <label class="field">
      <span class="t-descriptionSmall field-label">Height {shot.light.height}°</span>
      <input type="range" min="0" max="89" step="1" bind:value={shot.light.height} />
    </label>
    <label class="field">
      <span class="t-descriptionSmall field-label">
        Scroll {shot.scroll === undefined ? "auto" : `${Math.round(shot.scroll)}%`}
      </span>
      <input
        type="range"
        min="0"
        max="100"
        step="0.1"
        value={shot.scroll ?? (building ? 100 : 0)}
        oninput={(event) => (shot.scroll = Number(event.currentTarget.value))}
        ondblclick={() => (shot.scroll = undefined)}
      />
    </label>
  </section>

  <section class="panel-section">
    <h3 class="t-miniLabel section-title">Canvas</h3>
    <div class="field">
      <span class="t-descriptionSmall field-label">Size</span>
      <SegmentedControl
        segments={segmentsOf(sizes)}
        selection={shot.size}
        onSelect={(next) => (shot.size = next)}
      />
    </div>
    <OptionPicker
      title="Background"
      options={segmentsOf(backgrounds)}
      selection={shot.background}
      onSelect={(next) => (shot.background = next)}
    />
  </section>

  <section class="panel-section">
    <h3 class="t-miniLabel section-title">Headline</h3>
    <textarea
      class="showcase-textarea t-description"
      rows="3"
      placeholder="Returns break the line"
      bind:value={shot.headline}
    ></textarea>
    <div class="field">
      <span class="t-descriptionSmall field-label">Size</span>
      <SegmentedControl
        segments={segmentsOf(headlineSizes)}
        selection={shot.headlineSize}
        onSelect={(next) => (shot.headlineSize = next as HeadlineSize)}
      />
    </div>
    <OptionPicker
      title="Position"
      options={segmentsOf(anchors)}
      selection={shot.headlineAt}
      onSelect={(next) => (shot.headlineAt = next as Anchor)}
    />
  </section>
</aside>

<style>
  .panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n24);
    min-width: 0;
  }

  .panel-section {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: var(--spacing-n12);
  }

  .panel-title {
    margin: 0;
  }

  .section-title {
    margin: 0;
    padding-bottom: var(--spacing-n4);
    border-bottom: 1px solid var(--color-border-standard-base);
    color: var(--color-text-standard-muted);
  }

  /* A label column, so every control starts on the same line. */
  .field {
    display: grid;
    grid-template-columns: 76px minmax(0, 1fr);
    align-items: center;
    gap: var(--spacing-n12);
  }

  .field-label {
    color: var(--color-text-standard-muted);
    white-space: nowrap;
  }

  .field > input {
    width: 100%;
    margin: 0;
    accent-color: var(--color-interaction-active-fill);
  }

  .field > :global(*:last-child) {
    justify-self: start;
  }
</style>
