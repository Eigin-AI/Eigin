<script lang="ts">
  import { ActionButton, ContentGroup, IdentityHeader, NavigationHeader, Notice, Row } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import ScreenScroll from "@gallery/screens/ScreenScroll.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import {
    platformIntegration,
    platformIntegrations,
  } from "@gallery/screens/platform/platformIntegrations";

  let id = $state("health");
  let allows = $state("allowed");

  useStageControls(() => controls);

  const subject = $derived(platformIntegration(id));
  const access = $derived(subject.access[allows] ?? subject.access.allowed);

  /* Not every integration has every state, so switching subject starts over. */
  $effect(() => {
    if (!(allows in subject.access)) allows = "allowed";
  });

  /* Explains the kinds marked off, and leads into the link that fixes them. */
  const offNote = $derived.by(() => {
    if (access.off.length === 0 || access.notice) return undefined;
    return "iOS has turned off some access for Eigin.";
  });
  const lastGroup = $derived(subject.saves.length > 0 ? "saves" : "reads");
</script>

{#snippet controls()}
  <OptionSelector options={platformIntegrations.map((entry) => entry.id)} bind:value={id} />
  <OptionSelector options={Object.keys(subject.access)} bind:value={allows} />
{/snippet}

{#snippet kinds(label: string, group: string, names: string[])}
  {#if names.length > 0}
    <ContentGroup {label} footnote={group === lastGroup ? offNote : undefined}>
      {#each names as name (name)}
        {@const off = access.off.includes(`${group}/${name}`)}
        <Row title={name} value={off ? "Not allowed" : undefined} accessory="none" />
      {/each}
    </ContentGroup>
  {/if}
{/snippet}

<!--
  One integration that lives on the phone: Apple Health, Apple Calendar,
  Apple Reminders, Location.

  The same screen as any other integration, with what it reads and saves
  listed kind by kind. That list is the disclosure, so it reads the same to a
  person and to App Review.

  Like any integration, it is connected or it isn't: there are no switches
  here. A tool can still be narrowed in the agent's permissions. iOS owns the
  permission itself, so a kind iOS reports as off says so, and the link out is
  where that changes. Apple Health never says what it lets Eigin read, so only
  saving can show as off.
-->
<div class="platform">
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
      kind="On this phone"
      icon={subject.icon}
      state={access.notice ? "attention" : "connected"}
      status={access.notice?.status ?? "Connected"}
    />

    <!-- Only when it can't work at all. Tapping it goes where the link goes. -->
    {#if access.notice}
      <Notice
        tone="warning"
        title={access.notice.title}
        body={access.notice.body}
        onclick={() => {}}
      />
    {/if}

    {@render kinds("Eigin reads", "reads", subject.reads)}
    {@render kinds("Eigin saves", "saves", subject.saves)}

    <ContentGroup footnote="Change what Eigin can access in {subject.permissionIn}.">
      <Row title="Change access in {subject.permissionIn}" accessory="link" onclick={() => {}} />
    </ContentGroup>

    <ContentGroup>
      <Row title="Remove {subject.name}" accessory="trash" tone="destructive" onclick={() => {}} />
    </ContentGroup>
  </ScreenScroll>
</div>

<style>
  .platform {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }
</style>
