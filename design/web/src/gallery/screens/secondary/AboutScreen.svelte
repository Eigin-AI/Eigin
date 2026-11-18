<script lang="ts">
  import { ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
</script>

<SecondaryScreen title="About" back="settings">
  <ContentGroup>
    <Row title="Eigin" description="Version 1.0 (100) · Preview" accessory="none" />
  </ContentGroup>
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
  <ContentGroup label="Licenses">
    <Row
      title="Open source"
      description="Third-party packages"
      onclick={() => (location.hash = "#/screens/licenses")}
    />
    <Row
      title="Data sources"
      description="Services used by your agent"
      onclick={() => (location.hash = "#/screens/data-sources")}
    />
  </ContentGroup>
</SecondaryScreen>
