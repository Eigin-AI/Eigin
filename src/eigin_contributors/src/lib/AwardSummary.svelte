<script lang="ts">
  import CallSummary from "./CallSummary.svelte";
  let {
    call,
    closed = false,
  }: {
    closed?: boolean;
    call: {
      selectedAmountMinor: number;
      runnerUpAmountMinor: number;
      currency: string;
      closesAt: string;
      displayTimezone: string;
    };
  } = $props();
  const amount = (minor: number) =>
    new Intl.NumberFormat("en", {
      style: "currency",
      currency: call.currency,
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(minor / 100);
</script>

<CallSummary
  label="Funding"
  selected={amount(call.selectedAmountMinor)}
  runnerUp={amount(call.runnerUpAmountMinor)}
  closesAt={call.closesAt}
  timeZone={call.displayTimezone}
  {closed}
/>
