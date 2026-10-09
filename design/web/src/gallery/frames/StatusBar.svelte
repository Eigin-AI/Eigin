<script lang="ts">
  let { time = "9:41" }: { time?: string } = $props();
</script>

<!--
  Device chrome, not design system: the phone's own status bar, drawn so a
  screen is judged with the room its safe area actually leaves it. It follows
  iOS: SF Pro, and each side centred in the room beside the island.
-->
<div class="status-bar" aria-hidden="true">
  <span class="side">
    <span class="time">{time}</span>
  </span>

  <span class="island-gap"></span>

  <span class="side indicators">
    <svg class="signal" viewBox="0 0 18 12" fill="currentColor">
      <rect x="0" y="7.5" width="3.2" height="4.5" rx="1" />
      <rect x="4.9" y="5" width="3.2" height="7" rx="1" />
      <rect x="9.8" y="2.5" width="3.2" height="9.5" rx="1" />
      <rect x="14.7" y="0" width="3.2" height="12" rx="1" />
    </svg>

    <svg
      class="wifi"
      viewBox="0 0 17 12"
      fill="none"
      stroke="currentColor"
      stroke-width="2.1"
      stroke-linecap="round"
    >
      <path d="M1.6 4.5a10 10 0 0 1 13.8 0" />
      <path d="M4.4 7.3a6 6 0 0 1 8.2 0" />
      <path d="M8.5 11.2 6.9 9.6a2.3 2.3 0 0 1 3.2 0z" fill="currentColor" stroke-width="1.6" />
    </svg>

    <svg class="battery" viewBox="0 0 28 13">
      <rect
        x="0.5"
        y="0.5"
        width="24"
        height="12"
        rx="3.8"
        fill="none"
        stroke="currentColor"
        stroke-opacity="0.35"
      />
      <rect x="2" y="2" width="21" height="9" rx="2.5" fill="currentColor" />
      <path d="M26 4.5v4a2.2 2.2 0 0 0 0-4z" fill="currentColor" fill-opacity="0.4" />
    </svg>
  </span>
</div>

<style>
  .status-bar {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    /* The status bar occupies the top of the safe area the frame declares. */
    height: var(--eigin-safe-area-top, 59px);
    display: flex;
    align-items: flex-start;
    /* Lines the row up with the island's centre line. */
    padding: 18px 10px 0;
    box-sizing: border-box;
    color: var(--color-text-standard-base);
    font-family:
      system-ui,
      -apple-system,
      "SF Pro Text",
      sans-serif;
    pointer-events: none;
    z-index: 1;
  }

  .side {
    flex: 1;
    display: flex;
    justify-content: center;
    align-items: center;
    height: 22px;
  }

  /* As wide as the island, so the sides centre in the room beside it. */
  .island-gap {
    flex: none;
    width: 125px;
  }

  .time {
    font-size: 17px;
    font-weight: 600;
    letter-spacing: -0.4px;
    font-variant-numeric: tabular-nums;
    padding-left: 6px;
  }

  .indicators {
    gap: 6px;
  }

  .signal {
    width: 18px;
    height: 12px;
  }

  .wifi {
    width: 17px;
    height: 12px;
  }

  .battery {
    width: 28px;
    height: 13px;
  }
</style>
