<script lang="ts">
  import { FloatingPicker, Icon, PickerRow } from "@eigin/ui";

  let {
    open = $bindable(false),
    notesOpen,
    onFullscreen,
    onOverview,
    onNotes,
    onExport,
  }: {
    open?: boolean;
    notesOpen: boolean;
    onFullscreen: () => void;
    onOverview: () => void;
    onNotes: () => void;
    onExport: () => void;
  } = $props();
</script>

<FloatingPicker label="Menu" iconOnly bind:open>
  {#snippet trigger()}<Icon name="functional/dots/horizontal" size={24} />{/snippet}
  {#snippet children(dismiss)}
    <nav class="presentation-menu-actions" aria-label="Presentation actions" data-sveltekit-reload>
      <PickerRow
        onclick={() => {
          dismiss();
          onFullscreen();
        }}><span class="t-body">Fullscreen</span></PickerRow
      >
      <PickerRow
        onclick={() => {
          dismiss();
          onOverview();
        }}><span class="t-body">Slide overview</span></PickerRow
      >
      <PickerRow
        selected={notesOpen}
        onclick={() => {
          dismiss();
          onNotes();
        }}><span class="t-body">Speaker notes</span></PickerRow
      >
      <PickerRow
        onclick={() => {
          dismiss();
          onExport();
        }}><span class="t-body">Export PDF</span></PickerRow
      >
      <PickerRow href="/present/"><span class="t-body">Close presentation</span></PickerRow>
    </nav>
  {/snippet}
</FloatingPicker>

<style>
  .presentation-menu-actions {
    display: grid;
    gap: var(--spacing-n16);
  }
</style>
