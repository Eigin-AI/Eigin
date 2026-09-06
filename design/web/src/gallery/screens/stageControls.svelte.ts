import type { Snippet } from "svelte";

/**
 * A screen's own demo controls, rendered by the stage rather than inside the
 * phone. A control drawn on the screen itself is indistinguishable from the
 * design, so anything that only exists to drive the demo sits beside the
 * device pickers instead.
 *
 * Context flows down and the stage is an ancestor, so this is a module-level
 * holder: a screen sets it while mounted and clears it on the way out. Only
 * one screen is ever on the stage.
 */
const holder = $state<{ controls?: Snippet }>({});

export function stageControls() {
  return holder;
}

/** Publishes a screen's controls for as long as the screen is mounted. */
export function useStageControls(controls: () => Snippet | undefined) {
  $effect(() => {
    holder.controls = controls();
    return () => {
      holder.controls = undefined;
    };
  });
}
