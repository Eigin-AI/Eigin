<script lang="ts">
  import { AssetRow } from "@lib";
  import type { AssetState } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  const kinds = [
    "not installed",
    "queued",
    "downloading",
    "installed",
    "preparing",
    "ready",
    "failed",
    "unavailable",
  ] as const;
  let kind = $state<(typeof kinds)[number]>("downloading");

  const action = ["offered", "withheld"] as const;
  let showsAction = $state<(typeof action)[number]>("offered");

  const deletable = ["deletable", "kept"] as const;
  let canDelete = $state<(typeof deletable)[number]>("kept");

  const explainer = ["no explainer", "explainer"] as const;
  let withExplainer = $state<(typeof explainer)[number]>("no explainer");

  const states: Record<(typeof kinds)[number], AssetState> = {
    "not installed": { kind: "notDownloaded" },
    queued: { kind: "queued" },
    downloading: { kind: "downloading", fractionCompleted: 0.62, estimatedSecondsLeft: 42 },
    installed: { kind: "downloaded" },
    preparing: { kind: "preparing" },
    ready: { kind: "ready" },
    failed: { kind: "failed", message: "Network connection lost." },
    unavailable: { kind: "unavailable", reason: "You need at least 5.2 GB of free storage." },
  };
</script>

<div class="doc">
  <h2 class="t-titleM">Asset row</h2>
  <p class="lede t-description">
    One row for anything downloadable. A single circle carries the whole run — a track, an arc that
    grows, a fill when it lands — beside the name, a line of facts and one control. Numbers, not
    spinners. A warning states its reason and offers nothing to press.
  </p>

  <div class="controls">
    <!-- Eight states is wider than the column, so the track scrolls. -->
    <div class="wide">
      <OptionSelector options={kinds} bind:value={kind} />
    </div>
    <OptionSelector options={action} bind:value={showsAction} />
    <OptionSelector options={deletable} bind:value={canDelete} />
    <OptionSelector options={explainer} bind:value={withExplainer} />
  </div>

  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="stack">
        <AssetRow
          name="Gemma 4 E2B"
          state={states[kind]}
          sizeDescription="~2.6 GB"
          secondaryText={withExplainer === "explainer"
            ? "High-quality voice, entirely on device."
            : undefined}
          showsAction={showsAction === "offered"}
          onDownload={() => {}}
          onCancel={() => {}}
          onDelete={canDelete === "deletable" ? () => {} : undefined}
        />
      </div>
    </DeviceFrame>
  </div>
</div>

<style>
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  .wide {
    max-width: 100%;
    overflow-x: auto;
    scrollbar-width: none;
  }

  .wide::-webkit-scrollbar {
    display: none;
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
    max-width: 100%;
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
    padding: 0 var(--spacing-n16);
  }
</style>
