<script lang="ts">
  import {
    Button,
    ContentGroup,
    Icon,
    IdentityHeader,
    Notice,
    Row,
    Sheet,
    SubtleActionButton,
    TextInput,
  } from "@lib";
  import AiConsent from "@gallery/screens/AiConsent.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* How you got here, and how far you have got. The app knows both; here they
     are driven by hand. */
  const routes = ["sign in", "api key", "address"] as const;
  const steps = ["start", "working", "failed", "consent", "done"] as const;
  let route = $state<(typeof routes)[number]>("sign in");
  let step = $state<(typeof steps)[number]>("start");

  useStageControls(() => flowControl);

  let apiKey = $state("");
  let address = $state("api.infercom.eu");

  /* The name is offered rather than asked for: the domain is a good enough
     guess, and the one moment it is worth confirming is once the thing has
     actually answered. */
  const suggested = $derived.by(() => {
    const host = address.replace(/^https?:\/\//, "").split("/")[0];
    const label = host.split(".").filter((part) => part !== "www" && part !== "api")[0] ?? "";
    return label ? label[0].toUpperCase() + label.slice(1) : "Provider";
  });
  let chosenName = $state("");

  /* Filled in for you the moment the connection answers, and yours to change
     from there. */
  $effect(() => {
    if (step === "done" && !chosenName) chosenName = suggested;
  });

  const name = $derived(route === "address" ? chosenName || suggested : "OpenAI");

  const description = $derived(
    route === "sign in"
      ? "Sign in with OpenAI in your browser. Eigin never sees your password."
      : route === "api key"
        ? "Create a key in the OpenAI dashboard, then paste it here."
        : "Any service with an OpenAI-compatible API. You will need its address and a key.",
  );
</script>

{#snippet flowControl()}
  <OptionSelector options={routes} bind:value={route} />
  <OptionSelector options={steps} bind:value={step} />
{/snippet}

<!--
  Connecting one provider, whichever way it lets you in.

  The three routes ask for different things and fail differently, but they end
  the same: a header that says the connection is up, and one button back to
  where you were. Nothing here reports success before it has been checked.
-->
<Sheet
  bind:open
  title={step === "done"
    ? "Connected"
    : step === "consent"
      ? `Share with ${name}?`
      : route === "address"
        ? "Connect address"
        : name}
  description={step === "done"
    ? undefined
    : step === "consent"
      ? "To reply, Eigin sends your conversation to a cloud AI."
      : description}
>
  {#snippet primary()}
    <div class="flow">
      {#if step === "done"}
        <IdentityHeader
          {name}
          kind="AI provider"
          icon={route === "address" ? "functional/globe" : "provider/openai"}
          state="connected"
          status="Connected"
        />

        <!-- Named from its domain, and editable while it is still fresh: this
             is the one moment the guess is worth confirming. -->
        {#if route === "address"}
          <TextInput label="Name" bind:value={chosenName} />
        {/if}

        <ContentGroup
          footnote="3 of 47 appear in your agent tab. You can change it anytime on the provider's own screen."
        >
          <Row title="Models" value="47 available" accessory="none" />
        </ContentGroup>

        <Button label="Done" onclick={() => (open = false)} />
      {:else if step === "consent"}
        <!-- The last thing before the provider is saved: the check has passed,
             and nothing personal has been sent yet. Not now goes back to the
             list. -->
        <AiConsent
          recipient="own"
          {name}
          policyURL={route === "address"
            ? undefined
            : "https://openai.com/policies/privacy-policy/"}
          onAllow={() => (step = "done")}
          onDecline={() => (step = "start")}
        />
      {:else if step === "working"}
        <!-- A wait is something the screen is telling you, so it is a notice
             like any other. Nothing to press but the way out. -->
        <Notice
          tone="info"
          title={route === "sign in" ? "Waiting for you" : "Checking the connection"}
          body={route === "sign in"
            ? `Finish signing in with ${name} in your browser and this will continue by itself.`
            : "This can take a moment."}
        />

        <Button label="Cancel" variant="secondary" onclick={() => (step = "start")} />
      {:else if step === "failed"}
        <Notice
          tone="error"
          title={route === "sign in"
            ? "The sign-in did not finish"
            : route === "api key"
              ? "Your key was rejected"
              : "That address did not connect"}
          body={route === "sign in"
            ? `Something went wrong while connecting ${name}. You can try again, or choose another provider.`
            : route === "api key"
              ? `${name} did not accept it. Check that the key is valid and entered correctly.`
              : "Check that the address is right and that the key is valid and entered correctly."}
        />

        <!-- The same two ways out of every failure: this again, or something
             else entirely. Sending a failed sign-in to the key field instead
             was offering a route the person did not pick. -->
        <div class="actions">
          <Button label="Try again" onclick={() => (step = "start")} />
          <Button label="Choose another provider" variant="secondary" onclick={() => {}} />
        </div>
      {:else if route === "sign in"}
        <!-- One button, because the whole route is one decision: hand over to
             the browser and come back. -->
        <Button label="Continue with OpenAI" onclick={() => (step = "working")}>
          {#snippet trailing()}<Icon name="functional/arrow/up_right" size={16} />{/snippet}
        </Button>
      {:else if route === "api key"}
        <div class="actions">
          <TextInput label="API key" bind:value={apiKey} isSecure />
          <Button label="Connect" onclick={() => (step = "working")} disabled={!apiKey} />
          <SubtleActionButton label="Get an API key" size="medium" onclick={() => {}}>
            {#snippet icon()}<Icon name="functional/arrow/up_right" size={24} />{/snippet}
          </SubtleActionButton>
        </div>
      {:else}
        <!-- Address and key, the two things we cannot work out for ourselves.
             What it is called we can guess, so it is not asked for here. -->
        <div class="actions">
          <TextInput label="Address" bind:value={address} />
          <TextInput label="API key" bind:value={apiKey} isSecure />
          <Button
            label="Connect"
            onclick={() => (step = "working")}
            disabled={!address || !apiKey}
          />
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
