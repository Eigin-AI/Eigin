<script lang="ts">
  import { ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import SkillDetailScreen from "./SkillDetailScreen.svelte";
  import { skills } from "./skillsData";

  // Only skills backed by connected capabilities appear, as in iOS.
  const available = skills.filter(
    (skill) => !skill.capabilities.length || skill.capabilities.includes("email"),
  );
  let selected = $state<string>();
</script>

{#if selected}
  <SkillDetailScreen skillID={selected} onBack={() => (selected = undefined)} />
{:else}
  <SecondaryScreen title="Skills">
    <ContentGroup
      label="Available"
      footnote="Skills give your agent instructions for different kinds of work."
    >
      {#each available as skill (skill.id)}
        <Row
          title={skill.name}
          description={skill.description}
          onclick={() => (selected = skill.id)}
        />
      {:else}
        <Row title="Connect a capability to see its skills" accessory="none" tone="muted" />
      {/each}
    </ContentGroup>
  </SecondaryScreen>
{/if}
