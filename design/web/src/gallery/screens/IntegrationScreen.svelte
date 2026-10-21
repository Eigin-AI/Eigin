<script lang="ts">
  import {
    ActionButton,
    Button,
    ContentGroup,
    IdentityHeader,
    NavigationHeader,
    Notice,
    Row,
  } from "@lib";
  import type { ConnectionState, IconName } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  const kinds = ["built in", "MCP server", "agent"] as const;
  const conditions = ["connected", "reconnect", "unavailable"] as const;
  let kind = $state<(typeof kinds)[number]>("built in");
  let condition = $state<(typeof conditions)[number]>("connected");

  useStageControls(() => controls);

  /* One screen for three mechanisms: what differs is the name, the facts and
     what the thing offers. How it connects is a row, not a kind of screen. */
  const subject = $derived.by(() => {
    switch (kind) {
      case "MCP server":
        return {
          name: "Linear",
          icon: "service/linear" as IconName | undefined,
          letter: undefined,
          summary: "Issues and projects",
          via: "MCP server",
          detail: { title: "Address", value: "mcp.linear.app" },
          offers: {
            label: "Tools",
            items: ["Create issue", "Update issue", "Search issues", "List projects"],
            total: 20,
          },
        };
      case "agent":
        return {
          name: "Reeva",
          icon: undefined,
          letter: "R",
          summary: "Plans and books travel",
          via: "Agent",
          detail: { title: "Address", value: "reeva.travel" },
          offers: {
            label: "Skills",
            items: ["Find flights", "Book a hotel", "Rebook a trip"],
            total: 3,
          },
        };
      default:
        return {
          name: "Google",
          icon: "provider/google" as IconName,
          letter: undefined,
          summary: "Mail, calendar and contacts",
          via: "Built in",
          detail: { title: "Account", value: "you@example.com" },
          offers: { label: "What it can do", items: ["Mail", "Calendar", "Contacts"], total: 3 },
        };
    }
  });

  const status = $derived.by<{ state: ConnectionState; label: string }>(() => {
    if (condition === "reconnect") return { state: "attention", label: "Reconnect needed" };
    if (condition === "unavailable") return { state: "unavailable", label: "Unavailable" };
    return { state: "connected", label: "Connected" };
  });
</script>

<!-- The app reads both from the connection; here they are driven by hand. -->
{#snippet controls()}
  <OptionSelector options={kinds} bind:value={kind} />
  <OptionSelector options={conditions} bind:value={condition} />
{/snippet}

<!--
  One integration, whatever is behind it.

  A built-in account, a server someone runs and another agent are the same
  thing to the person using them: something Eigin can reach on their behalf.
  So they share a screen, and the mechanism is a fact row rather than a
  category — the only place in the app where the word MCP appears at all.
-->
<div class="integration">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader title={subject.name}>
        {#snippet leading()}
          <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
        {/snippet}
      </NavigationHeader>
    {/snippet}

    <IdentityHeader
      name={subject.name}
      kind={subject.summary}
      icon={subject.icon}
      letter={subject.letter}
      state={status.state}
      status={status.label}
    />

    {#if condition === "reconnect"}
      <Notice
        onclick={() => {}}
        tone="warning"
        title="The sign-in expired"
        body="Eigin cannot reach {subject.name} until you sign in again."
      />
    {:else if condition === "unavailable"}
      <Notice
        tone="error"
        title="{subject.name} is unavailable"
        body="The service is down, or you have lost connection."
      />
    {/if}

    <ContentGroup>
      <Row title="Connects via" value={subject.via} accessory="none" />
      <Row title={subject.detail.title} value={subject.detail.value} accessory="none" />
    </ContentGroup>

    <!-- What it can actually do, capped like any other long list. A busy
         server offers twenty tools, which would bury everything under it. -->
    <ContentGroup
      label={subject.offers.label}
      footnote={subject.offers.total > subject.offers.items.length
        ? `${subject.offers.total} in total, and Eigin picks the ones a chat needs.`
        : undefined}
    >
      {#each subject.offers.items as item (item)}
        <Row title={item} accessory="none" />
      {/each}
      {#if subject.offers.total > subject.offers.items.length}
        <Row
          title="Show all {subject.offers.total} {subject.offers.label.toLowerCase()}"
          tone="muted"
          onclick={() => (location.hash = "#/screens/integration-tools")}
        />
      {/if}
    </ContentGroup>

    {#if condition === "reconnect"}
      <Button label="Reconnect" onclick={() => {}} />
    {/if}

    <ContentGroup>
      <Row title="Remove {subject.name}" accessory="trash" tone="destructive" onclick={() => {}} />
    </ContentGroup>
  </ScreenScroll>
</div>

<style>
  .integration {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }
</style>
