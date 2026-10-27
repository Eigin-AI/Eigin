<script lang="ts">
  import { Tag } from "@eigin/ui";
  import type { DiagramLabels, TrustClaim } from "../content/trust/types";
  import AnimatedIllustration from "./AnimatedIllustration.svelte";
  import Disclosure from "./Disclosure.svelte";
  import DeviceDiagram from "./diagrams/DeviceDiagram.svelte";
  import ModelsDiagram from "./diagrams/ModelsDiagram.svelte";
  import ActionsDiagram from "./diagrams/ActionsDiagram.svelte";
  import SyncDiagram from "./diagrams/SyncDiagram.svelte";
  import MoneyDiagram from "./diagrams/MoneyDiagram.svelte";
  import OpenDiagram from "./diagrams/OpenDiagram.svelte";
  let { claim, more, diagrams }: { claim: TrustClaim; more: string; diagrams: DiagramLabels } =
    $props();
</script>

<section id={claim.id} class="trust-claim" aria-labelledby="{claim.id}-title">
  <div class="trust-claim-copy">
    <div class="trust-claim-label">
      <h2 class="t-miniLabel eyebrow" id="{claim.id}-title">{claim.title}</h2>
      {#if claim.status}<Tag label={claim.status} disabled />{/if}
    </div>
    <p class="t-titleM trust-statement">{claim.summary}</p>
  </div>
  <AnimatedIllustration class="trust-claim-diagram" labels={diagrams.motion}>
    {#if claim.diagram === "device"}<DeviceDiagram labels={diagrams.device} />
    {:else if claim.diagram === "models"}<ModelsDiagram labels={diagrams.models} />
    {:else if claim.diagram === "actions"}<ActionsDiagram labels={diagrams.actions} />
    {:else if claim.diagram === "sync"}<SyncDiagram labels={diagrams.sync} />
    {:else if claim.diagram === "money"}<MoneyDiagram labels={diagrams.money} />
    {:else}<OpenDiagram labels={diagrams.open} />{/if}
  </AnimatedIllustration>
  <Disclosure summary={more}>
    <ul class="trust-details t-body muted">
      {#each claim.details as detail}<li>{detail}</li>{/each}
    </ul>
  </Disclosure>
</section>
