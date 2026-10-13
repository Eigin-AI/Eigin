<script lang="ts">
  import {
    ActionButton,
    BrandAvatar,
    ChatBrandMessage,
    ChatFeed,
    ChatInput,
    ChatUserMessage,
    Icon,
    Markdown,
    NavigationHeader,
    ToolGroup,
  } from "@lib";
  import type { ToolCall, ToolStatus } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import ChooseIntegrationSheet from "@gallery/screens/ChooseIntegrationSheet.svelte";
  import ConnectPlatformSheet from "@gallery/screens/platform/ConnectPlatformSheet.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import type { ConnectPlatformStep } from "@gallery/screens/platform/platformIntegrations";

  const needs = ["health", "email"] as const;
  const moments = ["asking", "connected", "declined", "declined before"] as const;
  let need = $state<(typeof needs)[number]>("health");
  let moment = $state<(typeof moments)[number]>("asking");
  let step = $state<ConnectPlatformStep>("disclosure");
  let draft = $state("");
  let composerHeight = $state(0);

  useStageControls(() => controls);

  const agent = "Wren";

  /* Each need as a short exchange: what was asked, the skill the agent reaches
     for, and how the turn ends for each answer. */
  const script = $derived(
    need === "health"
      ? {
          ask: "How have I been sleeping this week?",
          lead: "Let me bring in my health skill for that.",
          use: { name: "Read sleep from Apple Health", result: "7 nights" },
          connected: `Six of seven nights over seven hours. **Tuesday was the outlier** at five and a half, and you were in bed past one.

Want me to keep an eye on it and say something if a short night repeats?`,
          declined:
            "No problem, I'll leave Apple Health alone. Tell me roughly how the nights have been and I can still help.",
          declinedBefore:
            "I can't use my health skill, since Apple Health isn't connected. If you'd like to give me access, you can add it in Settings, under Connections.",
        }
      : {
          ask: "Did Mia get back to me about Saturday?",
          lead: "Let me bring in my email skill to check.",
          use: { name: "Search mail", result: "1 match" },
          connected: `She did, this morning. **Saturday at ten works**, and she'll bring the kids' bikes.

Want me to put it in your calendar?`,
          declined:
            "No problem. I can't check without your email, so you'd need to look for Mia's reply yourself.",
          declinedBefore:
            "I can't use my email skill, since no email account is connected. If you'd like to give me access, you can add one in Settings, under Connections.",
        },
  );

  /* The activation is the call that waits. Its row says so while the sheet is
     up, and records the answer once there is one. After an earlier no it
     answers at once, declined, without asking again. */
  const tools = $derived.by<ToolCall[]>(() => {
    const status: ToolStatus =
      moment === "asking"
        ? "awaitingPermission"
        : moment === "connected"
          ? "completed"
          : "declined";
    const activation: ToolCall = { id: "activate", name: "Activate Skill", status };
    if (moment !== "connected") return [activation];
    return [activation, { id: "use", status: "completed", ...script.use }];
  });

  /* The sheet is the asking moment: open while the turn waits, closed by
     either answer. */
  let open = $state(false);
  $effect(() => {
    open = moment === "asking";
    if (moment === "asking") step = "disclosure";
  });
</script>

{#snippet controls()}
  <OptionSelector options={needs} bind:value={need} />
  <OptionSelector options={moments} bind:value={moment} />
{/snippet}

<!--
  The agent reaching for a skill whose integration isn't connected.

  As far as the agent knows it is only activating a skill. The skill needs a
  capability nothing provides, so the call waits and the app asks: the connect
  sheet opens over the chat, the way a permission request does. Connecting
  resumes the turn with the skill active; Not now hands the agent a refusal and
  it carries on without.

  It asks once. After a no, the skill stays findable but activating it answers
  straight away that the person declined. The call still shows, so it is plain
  why the agent can't help, and the agent says where to connect it instead.
-->
<div class="chat">
  <NavigationHeader>
    {#snippet leading()}
      <ActionButton icon="functional/note" variant="open" size="medium" label="Conversations" />
    {/snippet}
    {#snippet center()}
      <BrandAvatar emoji="🪶" label="Agent">
        <Icon name="brand/avatar" size="fill" />
      </BrandAvatar>
    {/snippet}
    {#snippet trailing()}
      <ActionButton icon="functional/phone" variant="open" size="medium" label="Call" />
    {/snippet}
  </NavigationHeader>

  <div class="scroll" style:padding-bottom="calc({composerHeight}px + var(--spacing-n16))">
    <ChatFeed>
      <ChatUserMessage text={script.ask} />

      <ChatBrandMessage>
        <Markdown text={script.lead} />
      </ChatBrandMessage>

      <ToolGroup {tools} />

      {#if moment !== "asking"}
        <ChatBrandMessage>
          <Markdown
            text={moment === "connected"
              ? script.connected
              : moment === "declined"
                ? script.declined
                : script.declinedBefore}
          />
        </ChatBrandMessage>
      {/if}
    </ChatFeed>
  </div>

  <div class="composer" bind:clientHeight={composerHeight}>
    <ChatInput bind:value={draft} isSendEnabled={draft.trim().length > 0} onActionTap={() => {}} />
  </div>

  <!-- One integration provides health, so the chat opens its connect sheet
       directly. Several provide email, so the person picks one first. -->
  {#if need === "health"}
    <ConnectPlatformSheet
      bind:open
      bind:step
      id="health"
      requestedBy={agent}
      onConnected={() => (moment = "connected")}
      onDeclined={() => (moment = "declined")}
    />
  {:else}
    <ChooseIntegrationSheet
      bind:open
      requestedBy={agent}
      onDeclined={() => (moment = "declined")}
    />
  {/if}
</div>

<style>
  .chat {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-surface-standard-base);
  }

  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }

  .composer {
    position: absolute;
    right: 0;
    bottom: 0;
    left: 0;
    padding-bottom: max(
      var(--spacing-n8),
      var(--eigin-safe-area-bottom, env(safe-area-inset-bottom))
    );
  }
</style>
