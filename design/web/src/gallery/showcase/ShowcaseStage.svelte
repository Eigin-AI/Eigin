<script lang="ts">
  import { Button } from "@lib";
  import ShotCanvas from "@gallery/showcase/ShotCanvas.svelte";
  import ShowcaseControls from "@gallery/showcase/ShowcaseControls.svelte";
  import { mainScroller, scrollPercent } from "@gallery/showcase/scroll";
  import { encodeShot, renderHash } from "@gallery/showcase/shotUrl";
  import {
    assetPath,
    sizeOf,
    type Format,
    type Placement,
    type Shot,
    type ShotEntry,
  } from "@gallery/showcase/shots";

  let { entry, initial }: { entry: ShotEntry; initial: Shot } = $props();

  // svelte-ignore state_referenced_locally
  let shot: Shot = $state(structuredClone(initial));
  let status = $state("");

  /* A transform rather than zoom: Safari holds zoomed text to a minimum
     size, which makes the phone's text too big. Never scales up, like the
     phone frames. */
  let available = $state(0);
  const fit = $derived(available ? Math.min(1, available / sizeOf(shot).width) : 1);

  /* The URL follows every change, so a link reproduces exactly this shot. */
  $effect(() => {
    const query = encodeShot(shot, entry).toString();
    history.replaceState(null, "", `#/showcase/${entry.id}${query ? `?${query}` : ""}`);
  });

  /* Dragging the preview moves the phone, in canvas percentages so the
     placement holds at every export size. */
  let drag: { x: number; y: number; from: Placement } | undefined;

  function startDrag(event: PointerEvent) {
    drag = { x: event.clientX, y: event.clientY, from: { ...shot.placement } };
    (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
  }

  function moveDrag(event: PointerEvent) {
    if (!drag) return;
    const size = sizeOf(shot);
    const round = (value: number) => Math.round(value * 2) / 2;
    shot.placement.x = round(drag.from.x + ((event.clientX - drag.x) / fit / size.width) * 100);
    shot.placement.y = round(drag.from.y + ((event.clientY - drag.y) / fit / size.height) * 100);
  }

  function exportRequest(format: Format, out?: string) {
    const size = sizeOf(shot);
    return fetch("/__showcase/export", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        hash: renderHash(entry.id, shot, entry),
        format,
        out,
        width: size.width,
        height: size.height,
      }),
    });
  }

  type SavePicker = (options: {
    suggestedName: string;
    types: { description: string; accept: Record<string, string[]> }[];
  }) => Promise<FileSystemFileHandle>;

  /* Asks where to save first, while the click still counts as a gesture.
     Browsers without a save dialog download the file instead. */
  async function exportShot(format: Format) {
    const name = `${entry.id}.${format}`;
    const type = format === "jpg" ? "image/jpeg" : "image/png";
    const picker = (window as unknown as { showSaveFilePicker?: SavePicker }).showSaveFilePicker;
    let handle: FileSystemFileHandle | undefined;
    if (picker) {
      try {
        handle = await picker({
          suggestedName: name,
          types: [{ description: format.toUpperCase(), accept: { [type]: [`.${format}`] } }],
        });
      } catch {
        return; // Cancelled.
      }
    }
    status = "Rendering…";
    const response = await exportRequest(format);
    if (!response.ok) {
      status = `Failed: ${await response.text()}`;
      return;
    }
    const image = await response.blob();
    if (handle) {
      const writable = await handle.createWritable();
      await writable.write(image);
      await writable.close();
      status = `Saved ${handle.name}`;
    } else {
      const link = document.createElement("a");
      link.href = URL.createObjectURL(image);
      link.download = name;
      link.click();
      URL.revokeObjectURL(link.href);
      status = `Downloaded ${name}`;
    }
  }

  /* The repo keeps JPEGs, at the shot's own path. */
  async function saveToRepo() {
    status = "Rendering…";
    const response = await exportRequest("jpg", assetPath(entry));
    status = response.ok ? `Saved ${await response.text()}` : `Failed: ${await response.text()}`;
  }

  /* The wheel over the preview sets the shot's scroll, which the canvas then
     applies. It is handled here rather than left to the browser, whose
     hit-testing misses the screen through the scaled, tilted phone. */
  function scrollPhone(node: HTMLElement) {
    const onWheel = (event: WheelEvent) => {
      const scroller = mainScroller(node);
      if (!scroller) return;
      event.preventDefault();
      const range = scroller.scrollHeight - scroller.clientHeight;
      const from = shot.scroll ?? scrollPercent(scroller);
      const next = from + (event.deltaY / fit / range) * 100;
      shot.scroll = Math.round(Math.min(100, Math.max(0, next)) * 10) / 10;
    };
    node.addEventListener("wheel", onWheel, { passive: false });
    return { destroy: () => node.removeEventListener("wheel", onWheel) };
  }

  /* Tweaks live in the URL until they are copied into shots.ts. */
  async function copySpec() {
    const { id, title, platform } = entry;
    await navigator.clipboard.writeText(JSON.stringify({ id, title, platform, ...shot }, null, 2));
    status = "Copied. Paste it into shots.ts to keep it.";
  }
</script>

<div class="stage showcase-stage">
  <ShowcaseControls bind:shot title={entry.title} />

  <div class="shot-fit" bind:clientWidth={available}>
    <div
      class="shot-scaled"
      use:scrollPhone
      style:width="{sizeOf(shot).width * fit}px"
      style:height="{sizeOf(shot).height * fit}px"
      role="presentation"
      onpointerdown={startDrag}
      onpointermove={moveDrag}
      onpointerup={() => (drag = undefined)}
      onpointercancel={() => (drag = undefined)}
    >
      <div class="shot-transform" style:transform="scale({fit})">
        <ShotCanvas {shot} />
      </div>
    </div>

    <div class="actions">
      <Button label="Export JPEG" size="small" onclick={() => exportShot("jpg")} />
      <Button
        label="Export PNG"
        variant="secondary"
        size="small"
        onclick={() => exportShot("png")}
      />
      <Button label="Save to repo" variant="open" size="small" onclick={saveToRepo} />
      <Button label="Copy spec" variant="open" size="small" onclick={copySpec} />
      {#if status}
        <p class="t-descriptionSmall status">{status}</p>
      {/if}
    </div>
  </div>
</div>

<style>
  /* Controls beside the shot, so a change and its result are both in view. */
  /* Visible overflow, or the stage becomes the scroller and the preview
     has nothing to stick to. */
  .showcase-stage {
    overflow: visible;
    display: grid;
    grid-template-columns: 360px minmax(0, 1fr);
    align-items: start;
    gap: var(--spacing-n32);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--spacing-n8);
  }

  .status {
    margin: 0;
    color: var(--color-text-standard-muted);
  }

  /* The preview and its exports ride along as the controls scroll. */
  .shot-fit {
    position: sticky;
    top: var(--spacing-n24);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
    min-width: 0;
  }

  .shot-transform {
    width: max-content;
    transform-origin: 0 0;
  }

  .shot-scaled {
    border-radius: var(--radius-card);
    overflow: hidden;
    cursor: grab;
    touch-action: none;
    user-select: none;
  }
</style>
