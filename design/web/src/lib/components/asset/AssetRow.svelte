<script lang="ts">
  import Icon from "../icon/Icon.svelte";
  import type { IconName } from "../../generated/icons";
  import { timeLeftText, type AssetState } from "./types";

  let {
    name,
    state,
    sizeDescription,
    secondaryText,
    showsAction = true,
    onDownload,
    onCancel,
    onDelete,
  }: {
    name: string;
    state: AssetState;
    /** Shown beside the installed/not-installed word, e.g. "~2.6 GB". */
    sizeDescription?: string;
    /** Explainer above the row: what this asset is, why it is offered. */
    secondaryText?: string;
    /** False where the screen owns the action itself, so it is not offered twice. */
    showsAction?: boolean;
    onDownload?: () => void;
    onCancel?: () => void;
    onDelete?: () => void;
  } = $props();

  type MetaTone = "muted" | "error" | "notice";

  const RING = 26;
  const STROKE = 4;
  const radius = (RING - STROKE) / 2;
  const circumference = 2 * Math.PI * radius;

  const joined = (...parts: (string | undefined)[]) => parts.filter(Boolean).join(" · ");

  /* One line of facts, never bytes and never a raw second count. */
  const meta = $derived.by<{ text: string; tone: MetaTone }>(() => {
    switch (state.kind) {
      case "notDownloaded":
        return { text: joined("Not installed", sizeDescription), tone: "muted" };
      case "queued":
        return { text: "Queued", tone: "muted" };
      case "downloading":
        return {
          text: joined(
            `${Math.round(state.fractionCompleted * 100)}%`,
            timeLeftText(state.estimatedSecondsLeft),
          ),
          tone: "muted",
        };
      case "downloaded":
        return { text: joined("Installed", sizeDescription), tone: "muted" };
      case "preparing":
        return {
          text:
            state.fractionCompleted === undefined
              ? "Preparing…"
              : `${Math.round(state.fractionCompleted * 100)}%`,
          tone: "muted",
        };
      case "ready":
        return { text: "Ready to use", tone: "muted" };
      case "failed":
        return { text: state.message, tone: "error" };
      case "unavailable":
        return { text: state.reason, tone: "notice" };
    }
  });

  /* A hair of arc from the first byte, so a transfer reads as started. */
  const arc = $derived.by(() => {
    switch (state.kind) {
      case "downloading":
        return Math.max(0.03, Math.min(1, state.fractionCompleted));
      case "downloaded":
      case "preparing":
      case "ready":
        return 1;
      default:
        return 0;
    }
  });

  /* Ready is excluded: a finished circle is a neutral fill, not an accent ring. */
  const showsArc = $derived(
    state.kind === "downloading" || state.kind === "downloaded" || state.kind === "preparing",
  );

  /* Queued and a fractionless preparing both drift: neither can be measured. */
  const sweeps = $derived(
    state.kind === "queued" ||
      state.kind === "downloaded" ||
      (state.kind === "preparing" && state.fractionCompleted === undefined),
  );

  /* Non-nil only for the informational states, which tint the ring rather
     than adding anything to it. */
  const signalTint = $derived(
    state.kind === "failed"
      ? "var(--color-icon-signal-negative)"
      : state.kind === "unavailable"
        ? "var(--color-icon-signal-notice)"
        : undefined,
  );

  /* Accent arrow to download, neutral x to cancel, neutral trash to delete.
     Nothing where the row has nothing to offer. */
  const control = $derived.by(() => {
    switch (state.kind) {
      case "notDownloaded":
      case "failed":
        return {
          key: "download",
          icon: "functional/arrow/down" as IconName,
          spot: true,
          run: onDownload,
        };
      case "queued":
      case "downloading":
        return { key: "cancel", icon: "functional/x" as IconName, spot: false, run: onCancel };
      case "ready":
        return onDelete
          ? { key: "delete", icon: "functional/trash" as IconName, spot: false, run: onDelete }
          : undefined;
      default:
        return undefined;
    }
  });
</script>

<!--
  One atom for anything downloadable: a progress circle, the name, one
  meta line of facts, one trailing control. Numbers rather than spinners —
  a transfer shows percent and, once a rate is stable, a time left. Warnings
  are informational: the reason is the copy, and there is no action in the row.
-->
<div class="asset">
  {#if secondaryText}
    <p class="t-note secondary">{secondaryText}</p>
  {/if}

  <div class="row">
    <!-- One circle that IS the progress: the track is always there, the arc
         grows with the transfer, and the fill closes it when ready. -->
    <span class="glyph">
      <svg viewBox="0 0 {RING} {RING}" width={RING} height={RING} aria-hidden="true">
        {#if !signalTint}
          <circle
            cx={RING / 2}
            cy={RING / 2}
            r={radius}
            fill="none"
            stroke="var(--color-border-standard-base)"
            stroke-width={STROKE}
          />
        {/if}

        {#if showsArc}
          <circle
            class="arc"
            cx={RING / 2}
            cy={RING / 2}
            r={radius}
            fill="none"
            stroke="var(--color-accent)"
            stroke-width={STROKE}
            stroke-linecap="round"
            stroke-dasharray="{circumference} {circumference}"
            stroke-dashoffset={circumference * (1 - arc)}
            transform="rotate(-90 {RING / 2} {RING / 2})"
          />
        {/if}

        {#if sweeps}
          <!-- A short arc drifting round the ring: waiting, not stuck. -->
          <circle
            class="sweep"
            cx={RING / 2}
            cy={RING / 2}
            r={radius}
            fill="none"
            stroke="var(--color-accent)"
            stroke-width={STROKE}
            stroke-linecap="round"
            stroke-dasharray="{circumference * 0.18} {circumference}"
          />
        {/if}

        {#if state.kind === "ready"}
          <circle
            cx={RING / 2}
            cy={RING / 2}
            r={RING / 2}
            fill="var(--color-border-standard-base)"
          />
        {/if}

        {#if signalTint}
          <circle
            cx={RING / 2}
            cy={RING / 2}
            r={radius}
            fill="none"
            stroke={signalTint}
            stroke-width={STROKE}
          />
        {/if}
      </svg>
    </span>

    <div class="text">
      <span class="t-titleXS name">{name}</span>
      <span class="t-note meta {meta.tone}">{meta.text}</span>
    </div>

    {#if showsAction && control}
      <button
        class="control"
        class:spot={control.spot}
        type="button"
        aria-label={control.key}
        onclick={control.run}
      >
        <Icon name={control.icon} size={17} />
      </button>
    {/if}
  </div>
</div>

<style>
  .asset {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n8);
  }

  .secondary {
    margin: 0;
    color: var(--color-text-standard-muted);
  }

  .row {
    display: flex;
    align-items: center;
    gap: var(--spacing-n16);
    box-sizing: border-box;
    padding: var(--spacing-n16) var(--spacing-n24);
    background: var(--color-surface-standard-alternative);
    border-radius: var(--radius-card);
  }

  .glyph {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: none;
    width: 34px;
    height: 34px;
  }

  .arc {
    transition: stroke-dashoffset 0.3s linear;
  }

  .sweep {
    transform-origin: center;
    animation: asset-sweep 1.6s linear infinite;
  }

  @keyframes asset-sweep {
    to {
      transform: rotate(360deg);
    }
  }

  /* n4 assumes untrimmed line boxes, which carry their own room above the
     cap and below the baseline. Trimmed, the same token reads as almost
     nothing — worst on the wrapping states, where the reason runs to several
     lines. Untrimmed here, so the gap stays real. */
  .text {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n4);
    min-width: 0;
  }

  .text > * {
    text-box: normal;
  }

  .name {
    color: var(--color-text-standard-base);
  }

  /* Digits hold their width, so a ticking percentage does not jitter. */
  .meta {
    font-variant-numeric: tabular-nums;
  }

  .meta.muted {
    color: var(--color-text-standard-muted);
  }

  .meta.error {
    color: var(--color-text-standard-error);
  }

  .meta.notice {
    color: var(--color-icon-signal-notice);
  }

  .control {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: none;
    width: 34px;
    height: 34px;
    margin-left: auto;
    padding: 0;
    border: none;
    border-radius: var(--radius-full);
    background: var(--color-button-navigation-base);
    color: var(--color-icon-standard-base);
    cursor: pointer;
  }

  .control.spot {
    background: var(--color-accent);
    color: var(--color-text-button-onSpot);
  }

  @media (prefers-reduced-motion: reduce) {
    .sweep {
      animation: none;
    }

    .arc {
      transition: none;
    }
  }
</style>
