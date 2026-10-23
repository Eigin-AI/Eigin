<script lang="ts">
  import { Button } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  import SettingsScreen from "../SettingsScreen.svelte";
  import FeedbackSheet from "./FeedbackSheet.svelte";
  let open = $state(true);
  let logging = $state("logging enabled");
  useStageControls(() => controls);
</script>

{#snippet controls()}<OptionSelector
    options={["logging enabled", "logging disabled"]}
    bind:value={logging}
  /><Button
    label="Reopen sheet"
    variant="secondary"
    size="small"
    onclick={() => (open = true)}
  />{/snippet}
<div class="host">
  <SettingsScreen /><FeedbackSheet bind:open logging={logging === "logging enabled"} />
</div>

<style>
  .host {
    position: relative;
    height: 100%;
  }
</style>
