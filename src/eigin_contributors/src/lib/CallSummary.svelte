<script lang="ts">
  import { CardSurface } from "@eigin/ui";
  let {
    label,
    selected,
    runnerUp,
    closesAt,
    timeZone,
    closed = false,
  }: {
    label: string;
    selected: string | null;
    runnerUp: string | null;
    closesAt: string;
    timeZone: string;
    closed?: boolean;
  } = $props();
  const closingDate = $derived(
    new Intl.DateTimeFormat("en-GB", {
      day: "numeric",
      year: closed ? "numeric" : undefined,
      month: "long",
      timeZone,
    }).format(new Date(closesAt)),
  );
  const closingTime = $derived(
    new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone,
    }).format(new Date(closesAt)),
  );
</script>

<CardSurface padding={24}>
  <div class="award-summary">
    <p class="t-miniLabel eyebrow">{label}</p>
    {#if selected !== null && runnerUp !== null}
      <dl class="award-amounts">
        <div>
          <dt class="t-note">Selected spec</dt>
          <dd><span class="t-titleM">{selected}</span></dd>
        </div>
        <div>
          <dt class="t-note">Runner-up spec</dt>
          <dd><span class="t-titleM">{runnerUp}</span></dd>
        </div>
      </dl>
    {:else}
      <p class="t-body">Results forthcoming</p>
    {/if}
    <div class="award-dates">
      <p class="t-miniLabel eyebrow">
        {closed ? "Closed" : "Closes"}
        {closingDate}
      </p>
      <p class="t-note">{closingTime} Copenhagen time</p>
    </div>
  </div>
</CardSurface>
