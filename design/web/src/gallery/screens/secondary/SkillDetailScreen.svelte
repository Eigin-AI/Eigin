<script lang="ts">
  import { ContentGroup, Row } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  import DetailText from "./DetailText.svelte";
  import { skills } from "./skillsData";
  import knowledgeInstruction from "./skillsText/knowledge.txt?raw";
  import emailInstruction from "./skillsText/email.txt?raw";

  // Only capability-backed skills appear, matching the list's availability rule.
  const instructions: Record<string, string> = {
    knowledge: knowledgeInstruction,
    email: emailInstruction,
  };
  let { skillID = "knowledge", onBack }: { skillID?: string; onBack?: () => void } = $props();
  const skill = $derived(skills.find((skill) => skill.id === skillID)!);
  const instruction = $derived(instructions[skill.id] ?? skill.description);
</script>

<SecondaryScreen title={skill.name} back="skills" {onBack}>
  <ContentGroup label="Instruction">
    <DetailText text={instruction} />
  </ContentGroup>
  {#if skill.tools.length}
    <ContentGroup label="Tools">
      {#each skill.tools as tool (tool)}
        <Row title={tool} accessory="none" />
      {/each}
    </ContentGroup>
  {/if}
</SecondaryScreen>
