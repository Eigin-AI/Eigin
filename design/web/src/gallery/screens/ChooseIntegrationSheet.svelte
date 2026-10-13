<script lang="ts">
  import { Button, ContentGroup, Row, Sheet } from "@lib";
  import type { IconName } from "@lib";

  let {
    open = $bindable(false),
    requestedBy,
    onDeclined,
  }: {
    open?: boolean;
    requestedBy: string;
    onDeclined?: () => void;
  } = $props();

  /* The same entries the catalogue lists under mail, in the same order. */
  const providers: { name: string; description: string; icon: IconName }[] = [
    { name: "Google", description: "Gmail", icon: "service/google" },
    { name: "Microsoft", description: "Outlook", icon: "service/microsoft" },
    { name: "iCloud", description: "iCloud mail", icon: "service/icloud" },
    { name: "Other email", description: "Any account with IMAP", icon: "functional/mail" },
  ];

  function decline() {
    open = false;
    onDeclined?.();
  }
</script>

<!--
  A chat asking for something more than one integration can provide.

  The agent asks for email, not for Gmail, so the sheet offers every way to get
  it and the person picks. Picking opens that integration's own connect sheet
  on top. When only one integration provides it, as with Apple Health, there is
  nothing to pick and the chat opens the connect sheet directly.
-->
<Sheet
  bind:open
  title="Connect email"
  description="{requestedBy} wants to use your email. Choose an account to connect."
  onDismiss={() => onDeclined?.()}
>
  {#snippet primary()}
    <div class="flow">
      <ContentGroup>
        {#each providers as provider (provider.name)}
          <Row
            title={provider.name}
            description={provider.description}
            icon={provider.icon}
            onclick={() => {}}
          />
        {/each}
      </ContentGroup>

      <Button label="Not now" variant="secondary" onclick={decline} />
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
</style>
