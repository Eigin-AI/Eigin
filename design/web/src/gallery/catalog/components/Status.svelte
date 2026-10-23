<script lang="ts">
  import {
    EmptyState,
    LoadingState,
    ContentGroup,
    IdentityHeader,
    Mark,
    Notice,
    Row,
    StatusLine,
  } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let emptyAction = $state("no action");
  let tone = $state("info");
  let mark = $state("logo");
</script>

<div class="doc">
  <h2 class="t-titleM">Empty state</h2>
  <p class="lede t-description">
    An icon, a title and a short explanation when there is no content. Add an action when there is a
    useful next step. The state fills the available space below the screen header.
  </p>
  <div class="controls">
    <OptionSelector options={["no action", "with action"]} bind:value={emptyAction} />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit"
      ><div class="state-example">
        <EmptyState
          icon="functional/grid"
          title="No spaces yet"
          description="Group related chats in a space, with instructions of their own."
          action={emptyAction === "with action" ? "Create space" : undefined}
          onclick={() => (location.hash = "#/screens/spaces")}
        />
      </div></DeviceFrame
    >
  </div>

  <h2 class="t-titleM">Loading state</h2>
  <p class="lede t-description">
    A larger indeterminate indicator and a title. No subtitle or estimated progress. Motion stops
    when reduced motion is enabled.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit"
      ><div class="state-example"><LoadingState title="Finding models" /></div></DeviceFrame
    >
  </div>

  <h2 class="t-titleM">Status line</h2>
  <p class="lede t-description">
    One vocabulary for "is this thing working": a dot and a word. Filled green is up, filled amber
    wants something from you, red is down through no fault of yours, hollow is not in use, and
    hollow pulsing is on its way. It is the only colour a connection screen carries, so the dot is
    always the first thing read — which only holds while everything that is fine stays silent. Amber
    and red divide by who can act: amber is a job, and the screen carries a button for it; red is an
    outage, so nothing appears beneath it.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="page">
        <div class="lines">
          <StatusLine state="connected" label="Connected" />
          <StatusLine state="connecting" label="Connecting" />
          <StatusLine state="attention" label="Reconnect needed" />
          <StatusLine state="unavailable" label="Unavailable" />
          <StatusLine state="off" label="Connects when used" />
          <StatusLine state="disabled" label="Disabled" />
        </div>

        <!-- Where it earns its keep: at the trailing edge of a row, in place
             of the chevron, on the one connection that needs you. -->
        <ContentGroup label="In a list">
          <Row title="Google" description="Mail, calendar and contacts" onclick={() => {}}>
            {#snippet trailing()}
              <StatusLine state="attention" label="Reconnect" />
            {/snippet}
          </Row>
          <Row title="Linear" description="Issues and projects" onclick={() => {}} />
        </ContentGroup>
      </div>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Mark</h2>
  <p class="lede t-description">
    A connection's face: its logo where we have one, its initial where we don't. Most of what people
    connect ships no asset — an IMAP account, a server someone runs, an agent at a URL — and a
    letter in the same circle keeps those from looking broken beside the ones that do. The layout
    never depends on whether an asset exists.
  </p>
  <div class="controls">
    <OptionSelector options={["logo", "letter", "emoji"]} bind:value={mark} />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="page center">
        <Mark
          icon={mark === "logo" ? "brand/chat_fill" : undefined}
          letter={mark === "letter" ? "A" : undefined}
          emoji={mark === "emoji" ? "🛫" : undefined}
        />
      </div>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Identity header</h2>
  <p class="lede t-description">
    The top of every connection screen: a mark, the name, what sort of thing it is, and whether it
    works. The same block whether it is a provider, a mail account, an MCP server or the model on
    the phone — so the screens read as one family however differently they are wired.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="page">
        <IdentityHeader
          name="Anthropic"
          kind="AI provider"
          letter="A"
          state="connected"
          status="Connected"
        />
      </div>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Notice</h2>
  <p class="lede t-description">
    Something the screen has to say before you read the rest. It carries no action of its own: the
    screen already has one slot for the thing worth doing, and a fix inside the card competed with
    it — two ways to reconnect, in two button languages, a few hundred points apart. The notice
    raises the problem, the primary button answers it, and the button always says something true.
  </p>
  <div class="controls">
    <OptionSelector options={["info", "warning", "error"]} bind:value={tone} />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="page">
        <Notice
          onclick={tone === "info" ? undefined : () => {}}
          tone={tone as "info" | "warning" | "error"}
          title={tone === "info"
            ? "Runs on this phone"
            : tone === "warning"
              ? "Google needs you again"
              : "That key was rejected"}
          body={tone === "info"
            ? "Nothing leaves the device, and it works with no signal."
            : tone === "warning"
              ? "The sign-in expired, so mail and calendar have stopped updating."
              : "Anthropic did not accept it. Check that it was copied whole."}
        />
      </div>
    </DeviceFrame>
  </div>
</div>

<style>
  .state-example {
    display: flex;
    min-height: 320px;
  }
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
  }

  .page {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
  }

  .center {
    align-items: center;
  }

  /* The states read as a set, so they sit at the grouping gap. */
  .lines {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }
</style>
