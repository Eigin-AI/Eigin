<script lang="ts">
  import { ContentGroup, Row, Sheet } from "@lib";
  import type { IconName } from "@lib";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  const points: { icon: IconName; title: string; body: string }[] = [
    {
      icon: "functional/speed/fast",
      title: "Used when you are offline",
      body: "With automatic routing, Eigin can use it when cloud AI is unavailable.",
    },
    {
      icon: "functional/hand",
      title: "Or chosen on purpose",
      body: "Pick it for conversations that should stay on your device only.",
    },
    {
      icon: "functional/sparkles",
      title: "Smaller than a cloud model",
      body: "Good for quick questions, weaker for complex tasks and tool use.",
    },
  ];
</script>

<!--
  What the on-device model is for, in the same card of rows the relay sheet
  uses: the screen states the facts, this answers the question behind them.
-->
<Sheet bind:open title="Local model" description="A small language model that runs on this device.">
  {#snippet primary()}
    <div class="points">
      <ContentGroup>
        {#each points as point (point.title)}
          <Row title={point.title} description={point.body} icon={point.icon} accessory="none" />
        {/each}
      </ContentGroup>
    </div>
  {/snippet}
</Sheet>

<style>
  .points {
    padding: 0 var(--spacing-n16);
  }
</style>
