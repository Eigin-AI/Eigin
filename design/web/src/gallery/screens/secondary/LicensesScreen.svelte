<script lang="ts">
  import { CardSurface, ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  // Snapshot of native LicenseEntry and LicenseTexts; no invented package metadata.
  import fixtures from "./licenseFixtures.json";
  import AttributionDetail from "./AttributionDetail.svelte";

  let selected = $state<(typeof fixtures.libraries)[number] | null>(null);

  const subtitle = (entry: (typeof fixtures.libraries)[number]) =>
    [entry.version ?? entry.distribution, entry.license].filter(Boolean).join(" · ");
</script>

{#if selected}
  <SecondaryScreen title={selected.name} onBack={() => (selected = null)}>
    <AttributionDetail heading={selected.copyright} provenance={subtitle(selected)}>
      <CardSurface><p class="t-tag license-text">{selected.text}</p></CardSurface>
      <ContentGroup>
        <Row
          title="Repository"
          accessory="link"
          onclick={() => window.open(selected?.repository, "_blank", "noopener,noreferrer")}
        />
      </ContentGroup>
    </AttributionDetail>
  </SecondaryScreen>
{:else}
  <SecondaryScreen title="Open source" back="about">
    <ContentGroup label="Libraries">
      {#each fixtures.libraries as entry (entry.name)}
        <Row title={entry.name} description={subtitle(entry)} onclick={() => (selected = entry)} />
      {/each}
    </ContentGroup>
    <ContentGroup label="Models">
      {#each fixtures.models as entry (entry.name)}
        <Row title={entry.name} description={subtitle(entry)} onclick={() => (selected = entry)} />
      {/each}
    </ContentGroup>
  </SecondaryScreen>
{/if}

<style>
  .license-text {
    margin: 0;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    user-select: text;
  }
</style>
