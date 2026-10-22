<script lang="ts">
  import { Button, ContentGroup, Row } from "@lib";

  interface Props {
    /** Who the conversation goes to: Eigin's relay, or a provider you connect. */
    recipient: "relay" | "own";
    /** The provider's name, or its domain when connected by address. */
    name?: string;
    /** The provider's own privacy policy. Without one, its terms go unlinked. */
    policyURL?: string;
    onAllow: () => void;
    onDecline: () => void;
  }

  const { recipient, name = "OpenAI", policyURL, onAllow, onDecline }: Props = $props();
</script>

<!--
  What is shared and where it goes, then the question.

  Shared by both ways into cloud AI: a step at the end of connecting your own
  provider, and a sheet of its own for the relay. Declining takes you back.
-->
<div class="consent">
  <ContentGroup label="What is shared">
    <!-- Ordered by how often it goes: always, when relevant, only if allowed. -->
    <Row
      title="This conversation"
      description="Your messages and attachments."
      icon="functional/note"
      accessory="none"
    />
    <Row
      title="Memories"
      description="From earlier chats, when relevant."
      icon="functional/sparkles"
      accessory="none"
    />
    <Row
      title="Connected data"
      description="Like calendar or reminders, if you allow it."
      icon="functional/search"
      accessory="none"
    />
    <Row title="Where it goes" icon="functional/globe" accessory="none">
      {#snippet descriptionContent()}
        {#if recipient === "relay"}
          Via Eigin to Corti, TensorX or Mistral. Chats are never stored. See our
          <a class="policy" href="https://www.eigin.ai/privacy/">privacy policy</a>.
        {:else if policyURL}
          Straight to {name}, under its
          <a class="policy" href={policyURL}>privacy policy</a>.
        {:else}
          Straight to {name}, under its own terms.
        {/if}
      {/snippet}
    </Row>
  </ContentGroup>

  <div class="actions">
    <Button label="Allow" onclick={onAllow} />
    <Button label="Not now" variant="secondary" onclick={onDecline} />
  </div>
</div>

<style>
  .consent {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-gap);
  }

  .policy {
    color: var(--color-text-standard-link);
  }

  .actions {
    display: flex;
    flex-direction: column;
    gap: var(--sizing-pageLayout-contentGrouping-gap);
  }
</style>
