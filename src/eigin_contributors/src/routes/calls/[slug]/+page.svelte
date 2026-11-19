<script lang="ts">
  import ClosedCallPage from "#lib/ClosedCallPage.svelte";
  import CallPage from "#lib/CallPage.svelte";
  let { data } = $props();
</script>

{#if data.closed || data.result}
  <ClosedCallPage
    result={data.result}
    call={data.call ? { ...data.call, brief: data.brief } : null}
  />
{:else}<CallPage {data} />{/if}
