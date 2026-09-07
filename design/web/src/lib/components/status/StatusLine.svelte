<script lang="ts">
  import type { ConnectionState } from "./types";

  const { state, label }: { state: ConnectionState; label: string } = $props();
</script>

<!--
  One vocabulary for "is this thing working": a dot and a word. Green is up,
  amber wants something from you, red is down through no fault of yours, and
  hollow is not in use. Nothing else on a connection screen is coloured, so the
  dot is always the first thing read.

  Amber and red divide by who can act. Amber is a job — a key to replace, a
  sign-in to renew — and the screen carries a button for it. Red is an outage:
  there is nothing to do but wait, so no button appears beneath it.
-->
<span class="status {state}">
  <span class="dot" aria-hidden="true"></span>
  <span class="t-tag">{label}</span>
</span>

<style>
  .status {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-n8);
    color: var(--color-text-standard-muted);
  }

  .dot {
    box-sizing: border-box;
    width: 8px;
    height: 8px;
    border-radius: var(--radius-full);
    border: 1.5px solid var(--color-text-standard-muted);
  }

  .connected .dot {
    border-color: var(--color-icon-signal-approve);
    background: var(--color-icon-signal-approve);
  }

  .attention .dot {
    border-color: var(--color-icon-signal-notice);
    background: var(--color-icon-signal-notice);
  }

  .unavailable .dot {
    border-color: var(--color-icon-signal-negative);
    background: var(--color-icon-signal-negative);
  }

  .attention,
  .unavailable {
    color: var(--color-text-standard-base);
  }

  .disabled {
    color: var(--color-text-standard-disabled);
  }

  .disabled .dot {
    border-color: var(--color-text-standard-disabled);
  }
</style>
