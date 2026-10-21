<script lang="ts">
  import {
    ActionButton,
    Button,
    ContentGroup,
    Icon,
    IdentityHeader,
    NavigationHeader,
    Notice,
    Row,
    SubtleActionButton,
    Switch,
  } from "@lib";
  import type { ConnectionState } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  const routes = ["API key", "Sign-in"] as const;
  const kinds = ["connected", "not working", "no credit", "none enabled"] as const;
  let route = $state<(typeof routes)[number]>("API key");
  let kind = $state<(typeof kinds)[number]>("connected");

  useStageControls(() => connection);

  /* Three of them, and the switch is the only thing worth doing here: a model
     you turn off stops crowding the picker in the agent tab. */
  let models = $state([
    { name: "Claude Opus 4.6", on: true },
    { name: "Claude Sonnet 4.6", on: true },
    { name: "Claude Haiku 4.5", on: true },
  ]);

  const enabled = $derived(kind === "none enabled" ? 0 : models.filter((m) => m.on).length);
  const broken = $derived(kind === "not working" || kind === "no credit");

  const status = $derived.by<{ state: ConnectionState; label: string }>(() => {
    if (kind === "not working") return { state: "attention", label: "Not working" };
    if (kind === "no credit") return { state: "attention", label: "Out of credit" };
    return { state: "connected", label: "Connected" };
  });

  const action = $derived(
    kind === "not working" ? (route === "API key" ? "Replace key" : "Sign in again") : undefined,
  );
</script>

<!-- The app reads this from the provider; here it is driven by hand. -->
{#snippet connection()}
  <OptionSelector options={routes} bind:value={route} />
  <OptionSelector options={kinds} bind:value={kind} />
{/snippet}

<!--
  A provider you connected yourself, whichever way you got in. A key and a
  sign-in differ in one fact row and in what the screen offers when they
  break, so they are one screen rather than two.

  Models carry no description: the provider does not give us one worth
  printing, and inventing a line per model would be worse than the name alone.
-->
<div class="provider">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader title="Anthropic">
        {#snippet leading()}
          <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
        {/snippet}
      </NavigationHeader>
    {/snippet}

    <IdentityHeader
      name="Anthropic"
      kind="AI provider"
      icon="provider/anthropic"
      state={status.state}
      status={status.label}
    />

    {#if kind === "not working"}
      <Notice
        onclick={() => {}}
        tone="warning"
        title={route === "API key" ? "The key stopped working" : "The sign-in expired"}
        body={route === "API key"
          ? "Anthropic rejected it on the last request. Keys can be revoked from their console."
          : "Anthropic asked for a fresh sign-in. This happens periodically."}
      />
    {:else if kind === "no credit"}
      <Notice
        onclick={() => {}}
        tone="warning"
        title="Your account is out of credit"
        body="The connection is fine. Top up with Anthropic and this works again."
      />
    {/if}

    <ContentGroup>
      <Row
        title="Connects via"
        value={route === "API key" ? "API key" : "Sign-in"}
        accessory="none"
      />
      {#if route === "API key"}
        <Row title="Key" value="sk-ant-••••4f2a" accessory="none" />
      {:else}
        <Row title="Account" value="you@example.com" accessory="none" />
      {/if}
    </ContentGroup>

    <!-- Forty-seven would bury the screen, so four and a way to the rest,
         where they can be searched. -->
    <ContentGroup
      label="Models"
      footnote={enabled === 0
        ? "With none turned on, Anthropic will not appear in your agent tab."
        : `${enabled} of 47 appear in your agent tab.`}
    >
      {#each models as model (model.name)}
        <Row title={model.name}>
          {#snippet trailing()}
            <Switch
              isOn={kind === "none enabled" ? false : model.on}
              disabled={broken}
              label={model.name}
              onclick={() => (model.on = !model.on)}
            />
          {/snippet}
        </Row>
      {/each}
      <Row
        title="Show all 47 models"
        tone="muted"
        onclick={() => (location.hash = "#/screens/provider-models")}
      />
    </ContentGroup>

    <!-- A rejected credential is ours to replace, so it gets the primary
         button. Topping up happens at the provider, so it is a link and looks
         like one: nothing in the app changes when you press it. -->
    {#if kind === "no credit"}
      <SubtleActionButton label="Open Anthropic console" size="medium" onclick={() => {}}>
        {#snippet icon()}<Icon name="functional/arrow/up_right" size={24} />{/snippet}
      </SubtleActionButton>
    {:else if action}
      <Button label={action} variant="primary" onclick={() => {}} />
    {/if}

    <ContentGroup>
      <Row title="Remove Anthropic" accessory="trash" tone="destructive" onclick={() => {}} />
    </ContentGroup>
  </ScreenScroll>
</div>

<style>
  .provider {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }
</style>
