<script lang="ts">
  import { Button, OptionsCarousel } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";
  import InferenceStep from "@gallery/screens/onboarding/InferenceStep.svelte";
  import { downloadStates, type DownloadStage } from "@gallery/screens/localModel";
  import NameStep from "@gallery/screens/onboarding/NameStep.svelte";
  import OnboardingChat from "@gallery/screens/onboarding/OnboardingChat.svelte";
  import OnboardingScaffold from "@gallery/screens/onboarding/OnboardingScaffold.svelte";
  import { introductions, type IntroductionLength } from "@gallery/screens/onboarding/conversation";
  import { TURN_TITLE_DELAY_MS, WELCOME_TITLE_DELAY_MS } from "@gallery/screens/onboarding/opening";
  import {
    avatarProgress,
    isSetupStep,
    priorities,
    speech,
    type OnboardingStep,
  } from "@gallery/screens/onboarding/steps";

  let { start = "welcome" }: { start?: OnboardingStep } = $props();

  const order: OnboardingStep[] = [
    "welcome",
    "name",
    "priority",
    "inference",
    "conversation",
    "reveal",
  ];

  /* Jumping in past the name step, the flow has a name to use. */
  // svelte-ignore state_referenced_locally
  const startsPastName = order.indexOf(start) > order.indexOf("name");

  // svelte-ignore state_referenced_locally
  let step = $state<OnboardingStep>(start);
  let name = $state(startsPastName ? "Alex" : "");
  let priority = $state(priorities[0].title);
  let credits = $state<"has credits" | "no credits">("has credits");
  let hardware = $state("supported device");
  let downloadStage = $state<DownloadStage>("not installed");
  const speeds = { "1×": 1, "½×": 0.5, "¼×": 0.25 };
  let speed = $state<keyof typeof speeds>("1×");
  let introduction = $state<IntroductionLength>("typical");
  /* Bumped to replay the flow from where this page starts it. */
  let run = $state(0);

  const line = $derived(speech(step, name.trim()));

  useStageControls(() => controls);

  function replay() {
    step = start;
    name = startsPastName ? "Alex" : "";
    run += 1;
  }
</script>

<!-- The app drives these from storage and the network; here they are by hand. -->
{#snippet controls()}
  <Button label="Replay" variant="secondary" size="small" onclick={replay} />
  {#if step === "reveal"}
    <OptionSelector options={Object.keys(speeds)} bind:value={speed} />
    <OptionSelector options={Object.keys(introductions)} bind:value={introduction} />
  {/if}
  {#if step === "inference"}
    <OptionSelector options={["has credits", "no credits"]} bind:value={credits} />
    <OptionSelector options={["supported device", "unsupported device"]} bind:value={hardware} />
    {#if hardware === "supported device"}
      <OptionSelector options={Object.keys(downloadStates)} bind:value={downloadStage} />
    {/if}
  {/if}
{/snippet}

<!--
  First launch, as one flow. The setup steps share one scaffold, so the
  avatar stays put and keeps filling as each line is spoken; the conversation
  takes over from there and ends in the agent's reveal.
-->
<!-- A new speed or introduction replays the reveal with it. -->
{#key `${run}-${speed}-${introduction}`}
  {#if isSetupStep(step)}
    <OnboardingScaffold
      progress={avatarProgress[step]}
      showsProgress={step !== "welcome"}
      entrance={step === "welcome"}
      turnId={step}
      title={line.title}
      text={line.text}
      titleDelay={step === "welcome" ? WELCOME_TITLE_DELAY_MS : TURN_TITLE_DELAY_MS}
    >
      {#if step === "welcome"}
        <div class="actions">
          <Button label="Begin" onclick={() => (step = "name")} />
        </div>
      {:else if step === "name"}
        <NameStep bind:name onContinue={() => (step = "priority")} />
      {:else if step === "priority"}
        <div class="carousel">
          <OptionsCarousel
            options={priorities.slice(0, 3).map((option) => ({
              label: option.title,
              description: option.explainer,
              symbol: option.symbol,
            }))}
            somethingElse={{
              label: priorities[3].title,
              description: priorities[3].explainer,
              symbol: priorities[3].symbol,
            }}
            focus="center"
            gap="var(--spacing-n16)"
            onSelect={(label) => {
              priority = label;
              step = "inference";
            }}
            onSomethingElse={() => {
              priority = priorities[3].title;
              step = "inference";
            }}
          />
        </div>
      {:else if step === "inference"}
        <InferenceStep
          hasCredits={credits === "has credits"}
          isSupported={hardware === "supported device"}
          bind:downloadStage
          onUseCloud={() => (step = "conversation")}
        />
      {/if}
    </OnboardingScaffold>
  {:else}
    <OnboardingChat
      name={name.trim()}
      {priority}
      revealing={step === "reveal"}
      speed={speeds[speed]}
      introduction={introductions[introduction]}
      onFinish={() => (step = "reveal")}
      onBack={() => (step = "inference")}
    />
  {/if}
{/key}

<style>
  .actions {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
    margin-top: auto;
  }

  /* Centred in the room under the line, bleeding past the padding so the
     neighbours peek in from the screen edges. */
  .carousel {
    display: flex;
    flex: 1;
    align-items: center;
    margin: 0 calc(-1 * var(--spacing-n24));
  }
</style>
