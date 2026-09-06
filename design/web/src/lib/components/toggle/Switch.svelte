<script lang="ts">
  import type { SwitchVariant } from "./types";

  let {
    isOn,
    variant = "positive",
    disabled = false,
    label = "Toggle",
    onclick,
  }: {
    isOn: boolean;
    /** Mirrors `AppSwitchVariant`. */
    variant?: SwitchVariant;
    disabled?: boolean;
    /** Accessible name for the control. */
    label?: string;
    onclick?: () => void;
  } = $props();
</script>

<!--
  Pill track with a sliding knob. Reflects `isOn` and
  calls back on tap, leaving state with the caller.
-->
<button
  type="button"
  role="switch"
  aria-checked={isOn}
  aria-label={label}
  class="track {variant}"
  class:on={isOn}
  {disabled}
  onclick={() => onclick?.()}
>
  <span class="knob"></span>
</button>

<style>
  .track {
    box-sizing: border-box;
    position: relative;
    width: var(--sizing-switch-track-width);
    height: var(--sizing-switch-track-height);
    padding: var(--sizing-switch-padding);
    border: none;
    border-radius: var(--radius-full);
    background: var(--color-input-standard-inactive);
    cursor: pointer;
    transition: background-color var(--motion-fast) var(--motion-easing-snap);
  }

  .track.on.positive {
    background: var(--color-interaction-active-fill);
  }

  .track:disabled {
    opacity: 0.5;
    cursor: default;
  }

  .knob {
    display: block;
    width: var(--sizing-switch-knob);
    height: var(--sizing-switch-knob);
    border-radius: var(--radius-full);
    background: var(--color-text-button-onSpot);
    transition: transform var(--motion-fast) var(--motion-easing-snap);
  }

  .track.on .knob {
    transform: translateX(
      calc(
        var(--sizing-switch-track-width) - var(--sizing-switch-knob) -
          var(--sizing-switch-padding) * 2
      )
    );
  }
</style>
