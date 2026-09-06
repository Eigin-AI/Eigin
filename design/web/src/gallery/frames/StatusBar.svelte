<script lang="ts">
  let { time = "9:41" }: { time?: string } = $props();
</script>

<!--
  Device chrome, not design system: the phone's own status bar, drawn so a
  screen is judged with the room its safe area actually leaves it.
-->
<div class="status-bar" aria-hidden="true">
  <span class="time">{time}</span>

  <span class="indicators">
    <svg class="signal" viewBox="0 0 18 12" fill="currentColor">
      <rect x="0" y="8" width="3" height="4" rx="1" />
      <rect x="5" y="5.5" width="3" height="6.5" rx="1" />
      <rect x="10" y="3" width="3" height="9" rx="1" />
      <rect x="15" y="0" width="3" height="12" rx="1" />
    </svg>

    <svg class="wifi" viewBox="0 0 16 12" fill="currentColor">
      <path
        d="M8 11.2 5.9 8.9a3 3 0 0 1 4.2 0zM3.9 6.9 2.5 5.4a7.8 7.8 0 0 1 11 0L12.1 6.9a5.8 5.8 0 0 0-8.2 0zM.6 3.5a11 11 0 0 1 14.8 0L14 5a9 9 0 0 0-12 0z"
      />
    </svg>

    <span class="battery">
      <span class="level"></span>
    </span>
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
    align-items: center;
    justify-content: space-between;
    padding: 0 30px 6px;
    box-sizing: border-box;
    color: var(--color-text-standard-base);
    font-family: var(--font-ui);
    pointer-events: none;
    z-index: 1;
  }

  .time {
    font-size: 16px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    letter-spacing: 0.2px;
  }

  .indicators {
    display: flex;
    align-items: center;
    gap: 5px;
  }

  .signal {
    width: 18px;
    height: 12px;
  }

  .wifi {
    width: 16px;
    height: 12px;
  }

  .battery {
    position: relative;
    display: inline-block;
    width: 25px;
    height: 12px;
    border: 1px solid currentColor;
    border-radius: 3px;
    opacity: 0.9;
  }

  /* The terminal nub on the right of the battery outline. */
  .battery::after {
    content: "";
    position: absolute;
    top: 3.5px;
    right: -3px;
    width: 2px;
    height: 4px;
    border-radius: 0 1px 1px 0;
    background: currentColor;
    opacity: 0.5;
  }

  .level {
    position: absolute;
    inset: 1.5px;
    width: 70%;
    border-radius: 1.5px;
    background: currentColor;
  }
</style>
