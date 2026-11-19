<script lang="ts">
  import CallSummary from "./CallSummary.svelte";
  import type { PublicCallCard } from "./publication.ts";
  let { call }: { call: PublicCallCard } = $props();
</script>

<CallSummary
  label="Results"
  selected={call.selectedAuthor}
  runnerUp={call.runnerUpAuthor}
  closesAt={call.closesAt}
  timeZone="Europe/Copenhagen"
  closed
/>
