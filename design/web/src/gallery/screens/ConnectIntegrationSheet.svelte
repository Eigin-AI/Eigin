<script lang="ts">
  import { Button, Icon, IdentityHeader, Notice, Sheet, SubtleActionButton, TextInput } from "@lib";
  import type { IconName } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { useStageControls } from "@gallery/screens/stageControls.svelte";

  let { open = $bindable(false) }: { open?: boolean } = $props();

  /* Five ways in, because integrations do not agree on one. The steps are the
     same for all of them; only the start differs. */
  const routes = ["sign in", "api key", "mail account", "preset server", "address"] as const;
  const steps = ["start", "working", "details", "failed", "done"] as const;
  let route = $state<(typeof routes)[number]>("sign in");
  let step = $state<(typeof steps)[number]>("start");

  useStageControls(() => controls);

  let apiKey = $state("");
  let address = $state("mcp.linear.app");
  let email = $state("");
  let password = $state("");
  let server = $state("");
  let smtpServer = $state("");
  let clientId = $state("");
  let clientSecret = $state("");
  let chosenName = $state("");

  const suggested = $derived.by(() => {
    const host = address.replace(/^https?:\/\//, "").split("/")[0];
    const label = host.split(".").filter((part) => part !== "www" && part !== "mcp")[0] ?? "";
    return label ? label[0].toUpperCase() + label.slice(1) : "Integration";
  });

  const subject = $derived.by<{ name: string; icon: IconName }>(() => {
    switch (route) {
      case "api key":
        return { name: "Home Assistant", icon: "service/homeassistant" };
      case "mail account":
        return { name: "Other email", icon: "functional/mail" };
      case "preset server":
        return { name: "Linear", icon: "service/linear" };
      case "address":
        /* Not named until it has answered: the sheet says what you are doing,
           and the name is offered at the end where it can be checked. */
        return {
          name: step === "done" ? chosenName || suggested : "Connect address",
          icon: "functional/globe",
        };
      default:
        return { name: "Google", icon: "service/google" };
    }
  });

  const description = $derived(
    route === "sign in"
      ? "Sign in with Google in your browser. Eigin never sees your password."
      : route === "api key"
        ? `Create a key with ${subject.name}, then paste it here.`
        : route === "mail account"
          ? "Your provider has these settings on their help pages. Most want an app password, not your own."
          : route === "preset server"
            ? "Connect Linear to Eigin. It will ask for whatever Linear needs."
            : "An MCP server, wherever it runs. The address is where we start.",
  );

  $effect(() => {
    if (step === "done" && route === "address" && !chosenName) chosenName = suggested;
  });
</script>

{#snippet controls()}
  <OptionSelector options={routes} bind:value={route} />
  <OptionSelector options={steps} bind:value={step} />
{/snippet}

<!--
  Connecting one integration, whichever way it lets you in.

  A built-in account signs in, a server you run wants a key, a mail account
  wants half a dozen settings, and a server at an address has to be asked what
  it needs before we can ask you for it. A preset is a single button over any
  of that: we know what it takes, so the person is asked only when there is
  something to give.

  Only the first step differs: waiting, failing and finishing are the same
  everywhere, so the distance between these five is as small as the mechanisms
  allow. Aula belongs to the sign-in route — it is a browser sign-in rather
  than OAuth, but that is a fact about the wiring, not about the step.
-->
<Sheet
  bind:open
  title={step === "done" ? "Connected" : subject.name}
  description={step === "done" ? undefined : description}
>
  {#snippet primary()}
    <div class="flow">
      {#if step === "done"}
        <IdentityHeader
          name={subject.name}
          kind="Integration"
          icon={subject.icon}
          state="connected"
          status="Connected"
        />

        <!-- Only the address route needs this: everywhere else the name came
             from the preset, not from a guess. -->
        {#if route === "address"}
          <TextInput label="Name" bind:value={chosenName} />
        {/if}

        <Button label="Done" onclick={() => (open = false)} />
      {:else if step === "working"}
        <Notice
          tone="info"
          title={route === "sign in" ? "Waiting for you" : "Checking the connection"}
          body={route === "sign in"
            ? `Finish signing in with ${subject.name} in your browser and this will continue by itself.`
            : "This can take a moment."}
        />

        <Button label="Cancel" variant="secondary" onclick={() => (step = "start")} />
      {:else if step === "details"}
        <!-- Only the address route reaches this: the server answered, and it
             wants credentials of its own rather than a sign-in. -->
        <Notice
          tone="info"
          title="This server wants its own credentials"
          body="It gave us a client ID and secret to ask for. Your provider issues these."
        />

        <div class="actions">
          <TextInput label="Client ID" bind:value={clientId} />
          <TextInput label="Client secret" bind:value={clientSecret} isSecure />
          <Button
            label="Connect"
            onclick={() => (step = "done")}
            disabled={!clientId || !clientSecret}
          />
        </div>
      {:else if step === "failed"}
        <Notice
          tone="error"
          title={route === "sign in"
            ? "The sign-in did not finish"
            : route === "api key"
              ? "Your key was rejected"
              : route === "mail account"
                ? "Those details did not work"
                : route === "preset server"
                  ? "Linear did not connect"
                  : "That address did not connect"}
          body={route === "sign in"
            ? `Something went wrong while connecting ${subject.name}. You can try again, or choose another integration.`
            : route === "api key"
              ? `${subject.name} did not accept it. Check that the key is valid and entered correctly.`
              : route === "mail account"
                ? "The server refused the sign-in. Check the address, and whether this account needs an app password."
                : route === "preset server"
                  ? "Linear did not answer. It may be down, so it is safe to try again."
                  : "Check that the address is right. If it needs credentials, it will ask for them next."}
        />

        <div class="actions">
          <Button label="Try again" onclick={() => (step = "start")} />
          <Button label="Choose another integration" variant="secondary" onclick={() => {}} />
        </div>
      {:else if route === "preset server"}
        <!-- A preset is one button, whatever is behind it: a sign-in, a key,
             credentials, or something stranger. Which one is a fact about the
             wiring, and it comes up when it is needed. -->
        <Button label="Continue with {subject.name}" onclick={() => (step = "working")} />
      {:else if route === "sign in"}
        <Button label="Continue with {subject.name}" onclick={() => (step = "working")}>
          {#snippet trailing()}<Icon name="functional/arrow/up_right" size={16} />{/snippet}
        </Button>
      {:else if route === "api key"}
        <div class="actions">
          <TextInput label="API key" bind:value={apiKey} isSecure />
          <Button label="Connect" onclick={() => (step = "working")} disabled={!apiKey} />
          <SubtleActionButton label="Where to find this" size="medium" onclick={() => {}}>
            {#snippet icon()}<Icon name="functional/arrow/up_right" size={24} />{/snippet}
          </SubtleActionButton>
        </div>
      {:else if route === "mail account"}
        <!-- The longest form in the app. Ports default to 993 and 587, and
             most providers put both hosts under one domain, so only what
             cannot be guessed is asked for. -->
        <div class="actions">
          <TextInput label="Email address" bind:value={email} />
          <TextInput label="App password" bind:value={password} isSecure />
          <TextInput label="IMAP server" bind:value={server} />
          <TextInput label="SMTP server" bind:value={smtpServer} />
          <Button
            label="Connect"
            onclick={() => (step = "working")}
            disabled={!email || !password || !server}
          />
        </div>
      {:else}
        <div class="actions">
          <TextInput label="Address" bind:value={address} />
          <Button label="Connect" onclick={() => (step = "working")} disabled={!address} />
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
