<script lang="ts">
  import { ContentGroup, Disclosure, SegmentedControl } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "../stageControls.svelte";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  let scenario = $state("connected tools");
  let levels = $state<Record<string, string>>({});
  const options = [
    { value: "never", label: "Never" },
    { value: "ask", label: "Ask" },
    { value: "always", label: "Always" },
  ];
  // Real tool display names; tools are not grouped into read/write categories.
  const categories = [
    {
      title: "Knowledge",
      tools: [
        "Search Knowledge",
        "Get Knowledge",
        "Add Knowledge",
        "Update Knowledge",
        "Delete Knowledge",
      ],
    },
    { title: "Web", tools: ["Web Search", "Web Fetch"] },
    {
      title: "Calendar",
      tools: ["Get Calendar Events", "Create Calendar Event", "Manage Calendar Event"],
    },
  ];
  useStageControls(() => controls);
</script>

{#snippet controls()}<OptionSelector
    options={["connected tools", "built-in only", "no tools discovered"]}
    bind:value={scenario}
  />{/snippet}
<SecondaryScreen title="Permissions" back="settings">
  <ContentGroup label="Built-in tools">
    {#each categories as category (category.title)}
      <Disclosure
        title={category.title}
        variant="open"
        initiallyExpanded={category.title === "Knowledge"}
      >
        <div class="permissions">
          {#each category.tools as tool (tool)}{@render permission(tool, false)}{/each}
        </div>
      </Disclosure>
    {/each}
  </ContentGroup>
  {#if scenario !== "built-in only"}
    <ContentGroup
      label="Connected tools"
      footnote="Default uses the shared permission for the connection."
    >
      <Disclosure title="Home Assistant" variant="open">
        {#if scenario === "no tools discovered"}<p class="t-navTab empty-note">
            No tools discovered.
          </p>
        {:else}<div class="permissions">
            {@render permission("Get state", true)}{@render permission("Call service", true)}
          </div>{/if}
      </Disclosure>
    </ContentGroup>
  {/if}
</SecondaryScreen>
{#snippet permission(title: string, discovered: boolean)}
  <div class="permission">
    <span class="t-navTab tool-name">{title}</span><SegmentedControl
      segments={discovered ? [{ value: "default", label: "Default" }, ...options] : options}
      selection={levels[title] ?? (discovered ? "default" : "ask")}
      onSelect={(value) => (levels[title] = value)}
    />
  </div>
{/snippet}

<style>
  .permissions {
    display: flex;
    flex-direction: column;
  }
  .permission {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
    padding: var(--spacing-n16) 0;
  }
  .permission:first-child {
    padding-top: 0;
  }
  .permission:last-child {
    padding-bottom: 0;
  }
  .empty-note {
    margin: 0;
    color: var(--color-text-standard-muted);
  }
  .tool-name {
    color: var(--color-text-standard-base);
  }
  .permission + .permission {
    border-top: 1px solid var(--color-input-standard-inactive);
  }
</style>
