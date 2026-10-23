<script lang="ts">
  import { ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  let licenses = $state(false);
</script>

<SecondaryScreen title="About" back="settings">
  <ContentGroup
    ><Row title="Eigin" description="Version 1.0 (100) · Preview" accessory="none" /></ContentGroup
  >
  <ContentGroup label="Legal">
    <Row
      title="Privacy policy"
      accessory="link"
      onclick={() => window.open("https://eigin.ai/privacy", "_blank", "noopener,noreferrer")}
    />
    <Row
      title="Terms of service"
      accessory="link"
      onclick={() => window.open("https://eigin.ai/terms", "_blank", "noopener,noreferrer")}
    />
  </ContentGroup>
  <ContentGroup label="Open source"
    ><Row
      title="Licenses"
      description="Third-party packages"
      onclick={() => (licenses = !licenses)}
    /></ContentGroup
  >
  {#if licenses}<p class="t-note" role="status">
      The iOS app lists package licenses here. License browsing is outside this preview.
    </p>{/if}
</SecondaryScreen>
