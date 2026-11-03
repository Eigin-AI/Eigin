<script lang="ts">
  import { onMount } from "svelte";
  import { ActionButton, Button, LinkButton } from "@eigin/ui";
  import { fetchSource, loadFile, loadFolder, loadZip, type Deck, type Directory } from "./sources";
  import { recents, saveRecent, type Recent } from "./recents";
  import "./present.css";
  import PresentationMenu from "./PresentationMenu.svelte";

  let { clean = false }: { clean?: boolean } = $props();
  let frame = $state<HTMLIFrameElement>(null!);
  let picker = $state<HTMLInputElement>(null!);
  let srcdoc = $state("");
  let error = $state("");
  let status = $state("idle");
  let menu = $state(false);
  let notes = $state<string | null>(null);
  let recent = $state<Recent[]>([]);
  let pendingFolder = $state<Recent | null>(null);
  let hasFolderPicker = $state(false);
  let mounted = $state(false);
  let printMode = $state(false);
  let printHeight = $state(720);
  let current = $state(1);
  let total = $state(0);
  let activeNotes = "";
  let channel = "";
  let params: URLSearchParams;
  let abort: AbortController;
  let disposed = false;
  let generation = 0;
  let timer: ReturnType<typeof setTimeout>;
  let readyTimer: ReturnType<typeof setTimeout>;
  let loader: (() => Promise<Deck>) | undefined;
  let lastMarkdown = "";
  let lastAssets = "";
  const assetRevision = (deck: Deck) =>
    JSON.stringify(
      deck.assets
        .map(([path, file]) => [path, file.size, file instanceof File ? file.lastModified : 0])
        .sort(),
    );
  let revision = 0;
  let initial = true;
  let frameLoaded = false;
  let nextDeck: Deck | undefined;
  let assetsModule: typeof import("./frame");

  function setStatus(value: string) {
    status = value;
    document.body.dataset.renderStatus = value;
  }
  function fail(reason: unknown) {
    if (disposed) return;
    error = reason instanceof Error ? reason.message : String(reason);
    setStatus("error");
    clearTimeout(readyTimer);
    scheduleWatch();
  }
  function post(type: string, data: object = {}) {
    frame?.contentWindow?.postMessage({ channel, type, ...data }, "*");
  }
  function sendDeck() {
    if (!frameLoaded || !nextDeck) return;
    const selected = params.get("slide");
    post("load", {
      generation,
      deck: assetsModule.frameDeck(nextDeck),
      options: {
        slide: clean && selected !== null ? Number.parseInt(selected, 10) || 1 : undefined,
        clean,
        print: printMode,
        hash: location.hash,
      },
    });
    nextDeck = undefined;
    clearTimeout(readyTimer);
    readyTimer = setTimeout(
      () => fail(new Error("Presentation did not become ready within 30 seconds.")),
      30000,
    );
  }
  function scheduleWatch() {
    clearTimeout(timer);
    if (!loader || printMode || disposed) return;
    timer = setTimeout(async () => {
      const version = generation;
      try {
        const deck = await loader!();
        if (disposed || version !== generation) return;
        if (
          deck.markdown !== lastMarkdown ||
          assetRevision(deck) !== lastAssets ||
          status === "error"
        ) {
          document.body.dataset.renderRev = String(++revision);
          await renderDeck(deck, version);
          return;
        }
      } catch (reason) {
        if (!disposed && version === generation)
          fail(
            new Error(
              "Live reload: " + (reason instanceof Error ? reason.message : String(reason)),
            ),
          );
        return;
      }
      scheduleWatch();
    }, 1000);
  }
  async function show(load: () => Promise<Deck>, watch = false) {
    const version = ++generation;
    clearTimeout(timer);
    clearTimeout(readyTimer);
    loader = watch ? load : undefined;
    error = "";
    setStatus("loading");
    readyTimer = setTimeout(() => fail(new Error("Loading the presentation timed out.")), 30000);
    try {
      const deck = await load();
      if (disposed || version !== generation) return;
      await renderDeck(deck, version);
    } catch (reason) {
      if (version === generation) fail(reason);
    }
  }
  async function renderDeck(deck: Deck, version: number) {
    lastMarkdown = deck.markdown;
    lastAssets = assetRevision(deck);
    nextDeck = deck;
    setStatus("loading");
    if (!srcdoc) {
      assetsModule = await import("./frame");
      if (disposed || version !== generation) return;
      srcdoc = assetsModule.frameDocument();
    } else sendDeck();
  }
  async function remember(record: Recent) {
    try {
      await saveRecent(record);
      recent = await recents();
    } catch {
      error = "This browser could not save the recent deck. The presentation is still available.";
    }
  }
  function renderSource(source: string) {
    const base = new URL(source, location.href).href;
    const watch =
      params.get("watch") !== "0" && (params.get("watch") === "1" || !params.has("slide"));
    void show(
      async () => ({
        markdown: await (await fetchSource(base, abort.signal)).text(),
        assets: [],
        baseUrl: base,
      }),
      watch,
    );
  }
  async function openFolder(record?: Recent) {
    try {
      const handle =
        record?.kind === "dir"
          ? record.handle
          : await (
              window as unknown as { showDirectoryPicker(): Promise<Directory> }
            ).showDirectoryPicker();
      if (
        (await handle.queryPermission({ mode: "read" })) !== "granted" &&
        (await handle.requestPermission({ mode: "read" })) !== "granted"
      )
        throw new Error("Folder access was not granted. Choose the folder again or load a ZIP.");
      const entry: Recent = {
        id: record?.id ?? "dir:" + crypto.randomUUID(),
        kind: "dir",
        handle,
        name: handle.name,
        lastOpened: Date.now(),
      };
      await remember(entry);
      const target = new URL(location.href);
      target.searchParams.delete("src");
      target.searchParams.set("deck", entry.id);
      history.replaceState(null, "", target);
      pendingFolder = null;
      await show(() => loadFolder(handle), params.get("watch") !== "0");
    } catch (reason) {
      if (!(reason instanceof DOMException && reason.name === "AbortError")) fail(reason);
    }
  }
  function fileSelected(file?: File) {
    if (!file) return;
    const target = new URL(location.href);
    target.search = "";
    target.hash = "";
    if (clean && params.has("slide")) target.searchParams.set("slide", params.get("slide")!);
    history.replaceState(null, "", target);
    void show(() => loadFile(file));
  }
  async function drop(event: DragEvent) {
    event.preventDefault();
    const item = event.dataTransfer?.items[0] as
      | (DataTransferItem & { getAsFileSystemHandle?(): Promise<Directory | FileSystemFileHandle> })
      | undefined;
    const file = event.dataTransfer?.files[0];
    try {
      const handle = await item?.getAsFileSystemHandle?.();
      if (handle?.kind === "directory") {
        await openFolder({
          id: "dir:" + crypto.randomUUID(),
          kind: "dir",
          handle: handle as Directory,
          name: handle.name,
          lastOpened: Date.now(),
        });
        return;
      }
      fileSelected(file);
    } catch (reason) {
      fail(reason);
    }
  }
  function exportPdf() {
    const target = new URL(location.href);
    if (!target.searchParams.has("deck")) {
      error = "PDF export needs a saved folder. Open this deck as a folder first.";
      return;
    }
    target.searchParams.set("print-pdf", "1");
    window.open(target, "_blank", "noopener,noreferrer");
  }
  async function fullscreen() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else {
        await document.querySelector(".presentation-player")?.requestFullscreen();
        menu = false;
        frame.focus();
      }
    } catch {
      error = "Fullscreen is unavailable in this browser. Use the browser’s fullscreen command.";
    }
  }
  onMount(() => {
    mounted = true;
    params = new URLSearchParams(location.search);
    setStatus("idle");
    printMode = params.has("print-pdf");
    channel = crypto.randomUUID();
    abort = new AbortController();
    hasFolderPicker = "showDirectoryPicker" in window;
    const message = (event: MessageEvent) => {
      const data = event.data;
      if (data?.generation !== generation) return;
      if (event.source !== frame?.contentWindow || !data || data.channel !== channel) return;
      if (
        (data.type === "ready" || data.type === "slide") &&
        Number.isInteger(data.total) &&
        data.total > 0 &&
        data.total <= 10000 &&
        Number.isInteger(data.current) &&
        data.current >= 1 &&
        data.current <= data.total
      ) {
        current = data.current;
        total = data.total;
        document.body.dataset.totalSlides = String(total);
        document.body.dataset.currentSlide = String(current);
        activeNotes = typeof data.notes === "string" ? data.notes.slice(0, 100000) : "";
        if (notes !== null) notes = activeNotes;
        if (!clean && !printMode && /^#\/\d+(\/\d+)?$/.test(data.hash))
          history.replaceState(null, "", location.pathname + location.search + data.hash);
        if (data.type === "ready") {
          clearTimeout(readyTimer);
          error = "";
          setStatus("ready");
          if (Number.isFinite(data.height))
            printHeight = Math.max(720, Math.min(720000, data.height));
          if (initial && !clean) frame.focus();
          initial = false;
          scheduleWatch();
        }
      } else if (data.type === "error" && typeof data.message === "string")
        fail(new Error(data.message.slice(0, 2000)));
      else if (!clean && data.type === "menu") menu = !menu;
      else if (!clean && data.type === "notes") notes = notes === null ? activeNotes : null;
      else if (!clean && data.type === "fullscreen") menu = true;
    };
    const keyboard = (event: KeyboardEvent) => {
      if (
        event.key.toLowerCase() === "m" &&
        !(
          event.target instanceof HTMLElement &&
          event.target.closest("input, textarea, [contenteditable]")
        )
      )
        menu = !menu;
    };
    const hash = () => {
      const match = location.hash.match(/^#\/(\d+)(?:\/(\d+))?/);
      if (match) post("navigate", { h: Number(match[1]), v: Number(match[2] ?? 0) });
    };
    const focusSlides = () => {
      if (document.activeElement === frame) menu = false;
    };
    window.addEventListener("blur", focusSlides);
    window.addEventListener("message", message);
    window.addEventListener("keydown", keyboard);
    window.addEventListener("hashchange", hash);
    if (!clean)
      void recents()
        .then(async (entries) => {
          recent = entries;
          const id = params.get("deck");
          if (id && !clean) {
            const entry = entries.find((entry) => entry.id === id);
            if (!entry || entry.kind !== "dir") {
              fail(new Error("This saved folder is unavailable in this browser. Choose it again."));
              return;
            }
            if ((await entry.handle.queryPermission({ mode: "read" })) === "granted")
              void show(() => loadFolder(entry.handle), params.get("watch") !== "0");
            else pendingFolder = entry;
          }
        })
        .catch(() => {
          if (params.has("deck"))
            fail(new Error("Saved folders are unavailable. Choose the folder again."));
        });
    if (clean && params.has("zip"))
      void show(async () => loadZip(await fetchSource(params.get("zip")!, abort.signal)));
    else if (clean && params.has("src")) {
      try {
        renderSource(params.get("src")!);
      } catch (reason) {
        fail(reason);
      }
    }
    return () => {
      disposed = true;
      generation++;
      abort.abort();
      clearTimeout(timer);
      clearTimeout(readyTimer);
      window.removeEventListener("blur", focusSlides);
      window.removeEventListener("message", message);
      window.removeEventListener("keydown", keyboard);
      window.removeEventListener("hashchange", hash);
      for (const key of ["renderStatus", "totalSlides", "currentSlide", "renderRev"])
        delete document.body.dataset[key];
    };
  });
</script>

<svelte:head
  ><title>{clean ? "Render presentation" : "Presentations"} · Eigin</title><meta
    name="robots"
    content="noindex, nofollow"
  /></svelte:head
>

{#if clean}
  <input
    class="presentation-file"
    bind:this={picker}
    type="file"
    accept=".zip,.md,.markdown,.txt"
    aria-label="Choose a presentation file"
    disabled={!mounted}
    onchange={() => fileSelected(picker.files?.[0])}
  />
  {#if !srcdoc}
    <main class="presentation-home t-body">
      <h1 class="t-titleXl">Render a local deck</h1>
      <p>Choose a ZIP containing deck.md and media, or a standalone Markdown file.</p>
      <Button label="Load ZIP or Markdown" disabled={!mounted} onclick={() => picker.click()} />
      <p>Files are read inside your browser. They are never uploaded.</p>
      <p>
        Agents can supply files through this input, wait for the render-ready marker, and capture
        slides. No website checkout or local server is needed.
      </p>
      <LinkButton
        href="/present/guide/#preview"
        label="Agent preview instructions"
        variant="secondary"
      />
    </main>
  {/if}
{/if}

{#if srcdoc}
  <main
    class="presentation-player"
    class:printing={printMode}
    class:menu-open={menu}
    style:--print-height={`${printHeight}px`}
  >
    <iframe
      bind:this={frame}
      title="Presentation slides"
      sandbox="allow-scripts"
      {srcdoc}
      onload={() => {
        frameLoaded = true;
        sendDeck();
      }}
    ></iframe>
    {#if !clean}
      <div class="presentation-controls">
        <PresentationMenu
          bind:open={menu}
          notesOpen={notes !== null}
          onFullscreen={fullscreen}
          onOverview={() => {
            post("overview");
            frame.focus();
          }}
          onNotes={() => (notes = notes === null ? activeNotes : null)}
          onExport={exportPdf}
        />
      </div>
      {#if printMode}
        <div class="presentation-print">
          <Button label="Print / Save PDF" size="small" onclick={() => window.print()} />
        </div>
      {/if}
      {#if notes !== null}<aside class="presentation-notes" aria-label="Speaker notes">
          <header class="presentation-notes-header">
            <div>
              <p class="t-miniLabel">Slide {current} / {total}</p>
              <h2 class="t-titleS">Speaker notes</h2>
            </div>
            <Button
              label="Close notes"
              variant="secondary"
              size="small"
              onclick={() => (notes = null)}
            />
          </header>
          <div class="presentation-notes-copy t-body">{notes || "No notes for this slide."}</div>
        </aside>{/if}
    {/if}
  </main>
{:else if !clean}
  <main class="presentation-home t-body">
    <nav class="presentation-topbar" aria-label="Presentation navigation">
      <a href="/" class="t-titleS">Eigin</a>
      <span class="t-miniLabel">Presentation system</span>
    </nav>
    <header class="presentation-intro">
      <h1 class="t-display">Ready to present.</h1>
      <p class="t-standfirst">Open a presentation and make it yours.</p>
    </header>
    <div class="presentation-launch-grid">
      <div
        class="presentation-drop"
        role="region"
        aria-label="Drop a presentation"
        ondragover={(event) => event.preventDefault()}
        ondrop={drop}
      >
        <input
          bind:this={picker}
          type="file"
          accept=".zip,.md,.markdown,.txt"
          aria-label="Choose a presentation file"
          disabled={!mounted}
          onchange={() => fileSelected(picker.files?.[0])}
        />
        <p class="t-miniLabel">01 / Present</p>
        <h2 class="t-titleM">Open your deck</h2>
        <p>
          {#if hasFolderPicker}Choose a folder to preview changes as you write, or open a ZIP to get
            straight to the slides.
          {:else}Open a ZIP with your deck and media, or choose a standalone Markdown file.{/if}
        </p>
        <div class="presentation-actions">
          {#if hasFolderPicker}<Button
              label="Open folder"
              size="medium"
              onclick={() => openFolder()}
            />{/if}
          <Button
            label="Load ZIP or Markdown"
            size="medium"
            variant={hasFolderPicker ? "secondary" : "primary"}
            disabled={!mounted}
            onclick={() => picker.click()}
          />
        </div>
        <p class="presentation-hint t-note">
          You can also drop a folder, ZIP, or Markdown file here. ZIPs work across browsers.
        </p>
      </div>
      <section class="presentation-guide-card" aria-label="Create a presentation">
        <p class="t-miniLabel">02 / Create</p>
        <h2 class="t-titleM">Create a deck</h2>
        <p>Layouts, writing rules, assets, and preview instructions for authors and agents.</p>
        <LinkButton
          href="/present/guide/"
          label="Authoring guide"
          size="medium"
          variant="secondary"
        />
      </section>
    </div>
    {#if pendingFolder}<Button
        label={`Allow access to ${pendingFolder.name}`}
        onclick={() => openFolder(pendingFolder!)}
      />{/if}
    {#if recent.length}
      <h2 class="t-titleM">Recent decks</h2>
      <table class="presentation-recents" aria-label="Recent decks">
        <thead
          ><tr
            ><th scope="col" class="t-miniLabel">Deck</th><th scope="col" class="t-miniLabel"
              >Actions</th
            ></tr
          ></thead
        >
        <tbody>
          {#each recent.slice(0, 6) as entry (entry.id)}
            <tr>
              <th scope="row" class="t-body">{entry.name}</th>
              <td>
                <div class="presentation-recent-actions">
                  <Button
                    label="Open"
                    variant="open"
                    size="small"
                    onclick={() => openFolder(entry)}
                  />
                  <ActionButton
                    icon="functional/x"
                    label={`Forget ${entry.name}`}
                    variant="open"
                    size="small"
                    onclick={async () => {
                      try {
                        await saveRecent(entry.id);
                        recent = await recents();
                      } catch (reason) {
                        fail(reason);
                      }
                    }}
                  />
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    {/if}
  </main>
{/if}
{#if status === "loading"}<div class="presentation-status" role="status">
    Loading presentation…
  </div>{/if}
{#if error}<div class="presentation-error" role="alert">
    {error} <a href="/present/" data-sveltekit-reload>Open another deck</a>
  </div>{/if}
