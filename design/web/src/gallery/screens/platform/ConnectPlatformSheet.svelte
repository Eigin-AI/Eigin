<script lang="ts">
  import { Button, ContentGroup, IdentityHeader, Notice, Row, Sheet } from "@lib";
  import {
    platformIntegration,
    listed,
    type ConnectPlatformStep,
  } from "@gallery/screens/platform/platformIntegrations";

  let {
    open = $bindable(false),
    id,
    step = $bindable("disclosure"),
    requestedBy,
    onConnected,
    onDeclined,
  }: {
    open?: boolean;
    id: string;
    step?: ConnectPlatformStep;
    /** The agent asking, when a chat opened this rather than the person. */
    requestedBy?: string;
    onConnected?: () => void;
    /** Not now, or closing the sheet before connecting: the chat carries on
        without it. */
    onDeclined?: () => void;
  } = $props();

  const subject = $derived(platformIntegration(id));

  const description = $derived(
    requestedBy
      ? `${requestedBy} wants to use ${subject.name}. iOS asks what to allow next.`
      : "iOS asks what to allow next.",
  );

  /* From a chat the agent is waiting, so the last step says Continue and
     hands back to it rather than just closing. */
  function finish() {
    open = false;
    if (requestedBy) onConnected?.();
  }

  function decline() {
    open = false;
    onDeclined?.();
  }

  /* Reading and saving the same thing is one line, not two that echo. */
  const asks = $derived.by(() => {
    const same =
      subject.reads.length === subject.saves.length &&
      subject.reads.every((kind) => subject.saves.includes(kind));
    if (same) return [{ verb: "Eigin reads and saves", kinds: subject.reads }];
    return [
      { verb: "Eigin reads", kinds: subject.reads },
      { verb: "Eigin saves", kinds: subject.saves },
    ].filter((entry) => entry.kinds.length > 0);
  });
</script>

<!--
  The one way an integration on the phone gets connected, from wherever it was
  asked for: the catalogue, its own screen, or the agent in a chat.

  From a chat it also says who is asking, and offers Not now: the agent's turn
  waits on the answer either way.

  It says what Eigin will read and save before iOS asks, because the system
  prompt names the data but never says why or where it goes. Then it steps
  aside: the permission is iOS's, so the sheet waits for it rather than
  repeating it.
-->
<Sheet
  bind:open
  title={step === "done" ? "Connected" : `Connect ${subject.name}`}
  description={step === "disclosure" ? description : undefined}
  onDismiss={requestedBy ? () => (step === "done" ? onConnected?.() : onDeclined?.()) : undefined}
>
  {#snippet primary()}
    <div class="flow">
      {#if step === "done"}
        <IdentityHeader
          name={subject.name}
          kind="On this phone"
          icon={subject.icon}
          state="connected"
          status="Connected"
        />
        <Button label={requestedBy ? "Continue" : "Done"} onclick={finish} />
      {:else if step === "asking"}
        <!-- iOS answers in the app; here a tap stands in for allowing. -->
        <Notice
          onclick={() => (step = "done")}
          tone="info"
          title="Waiting for you"
          body="Choose what to allow in {subject.askedBy}, and this will continue by itself."
        />
      {:else if step === "refused"}
        <!-- iOS asks once. After a no, the only way back is Settings, so the
             sheet says so rather than offering to ask again. -->
        <Notice
          tone="warning"
          title="{subject.name} is off for Eigin"
          body="iOS won't ask again. Allow Eigin in {subject.permissionIn}, then come back."
        />
        <Button label="Open {subject.permissionIn}" onclick={() => {}} />
      {:else}
        <!-- Brief on purpose: everything it will ask for, in a line or two above
             the button. Each kind gets its own switch once connected. -->
        <ContentGroup>
          {#each asks as entry (entry.verb)}
            <Row title={entry.verb} description={listed(entry.kinds)} accessory="none" />
          {/each}
        </ContentGroup>

        <div class="actions">
          <Button label="Continue" onclick={() => (step = "asking")} />
          {#if requestedBy}
            <Button label="Not now" variant="secondary" onclick={decline} />
          {/if}
        </div>
      {/if}
    </div>
  {/snippet}
</Sheet>

<style>
  .flow {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
    padding: 0 var(--spacing-n16);
  }

  .actions {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }
</style>
