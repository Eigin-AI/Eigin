<script lang="ts">
  import SubtleActionButton from "../button/SubtleActionButton.svelte";
  import Icon from "../icon/Icon.svelte";
  import type { SheetAction } from "./types";

  interface Props {
    actions: SheetAction[];
  }

  const { actions }: Props = $props();
</script>

<!--
  A sheet whose whole content is a short list of
  actions. Labels are passed in, so the component stays locale-agnostic.
-->
<div class="actions">
  {#each actions as action (action.label)}
    <SubtleActionButton label={action.label} disabled={action.disabled} onclick={action.onclick}>
      {#snippet icon()}<Icon name={action.icon} size={24} />{/snippet}
    </SubtleActionButton>
  {/each}
</div>

<style>
  .actions {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
    /* Sheet content sits on the outer grid column, unlike the header's text. */
    padding: 0 var(--sizing-pageLayout-contentGrouping-px-mobile);
  }

  @container eigin (min-width: 768px) {
    .actions {
      padding: 0 var(--sizing-pageLayout-contentGrouping-px-tablet);
    }
  }

  @container eigin (min-width: 1280px) {
    .actions {
      padding: 0 var(--sizing-pageLayout-contentGrouping-px-desktop);
    }
  }
</style>
