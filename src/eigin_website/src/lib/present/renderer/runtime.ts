import type { DeckRenderer } from "./deck-types";

/** Runs only inside the opaque-origin iframe; receives no website privileges. */
export function rendererRuntime() {
  type Options = {
    slide?: number;
    clean: boolean;
    print: boolean;
    hash: string;
  };
  type Deck = { markdown: string; assets: [string, Blob][]; baseUrl?: string };
  type RevealApi = {
    getSlides(): HTMLElement[];
    getCurrentSlide(): HTMLElement;
    getIndices(slide?: HTMLElement): { h: number; v?: number };
    slide(h: number, v?: number): void;
    toggleOverview(): void;
    layout(): void;
    on(event: string, callback: () => void): void;
    getPlugin(name: string): { layout(): Promise<void> };
  };
  const globals = window as unknown as {
    Reveal: RevealApi;
    EiginPresent: DeckRenderer;
  };
  const reveal = globals.Reveal;
  const core = globals.EiginPresent;
  let initialized = false;
  let busy = false;
  let latestGeneration = 0;
  let activeGeneration = 0;
  let interrupt: (() => void) | undefined;
  let pending: { deck: Deck; options: Options; generation: number } | undefined;
  let urls: string[] = [];
  let options: Options;
  let channel = "";
  const send = (type: string, data: object = {}) =>
    parent.postMessage({ channel, generation: activeGeneration, type, ...data }, "*");
  const metadata = () => {
    const slides = reveal.getSlides();
    const current = reveal.getCurrentSlide();
    const indices = reveal.getIndices();
    return {
      total: slides.length,
      current: slides.indexOf(current) + 1,
      hash: `#/${indices.h}${indices.v ? "/" + indices.v : ""}`,
      notes: current?.querySelector(".notes")?.textContent ?? "",
    };
  };
  async function settle() {
    await document.fonts.ready;
    const images = [...document.querySelectorAll<HTMLImageElement>("img")];
    // Reveal only loads nearby slides; readiness covers every deck image.
    for (const image of images) {
      if (image.dataset.src) {
        image.src = image.dataset.src;
        image.removeAttribute("data-src");
      }
    }
    const backgrounds = [...document.querySelectorAll<HTMLElement>("[data-background-image]")].map(
      (el) => {
        const image = new Image();
        image.src = el.dataset.backgroundImage!;
        return image;
      },
    );
    await Promise.all(
      [...images, ...backgrounds].map((image) =>
        image.decode().catch(() => {
          throw new Error("Could not load image: " + image.getAttribute("src"));
        }),
      ),
    );
    await new Promise<void>((resolve) =>
      requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
    );
  }
  async function load(deck: Deck, settings: Options) {
    const interrupted = new Promise<void>((resolve) => {
      interrupt = resolve;
    });
    options = settings;
    const oldUrls = urls;
    urls = [];
    const assets = new Map(
      deck.assets.map(([path, blob]) => {
        const url = URL.createObjectURL(blob);
        urls.push(url);
        return [path, url];
      }),
    );
    function resolve(ref: string): string | null {
      const key = ref.replace(/^\.\//, "").toLowerCase();
      const local = assets.get(key) ?? assets.get("media/" + key);
      if (local) return local;
      if (/^[a-z]+:|^\//i.test(ref)) return null;
      return deck.baseUrl ? new URL(ref, deck.baseUrl).href : null;
    }
    let printReady: Promise<void> | undefined;
    if (!initialized) {
      if (options.print)
        printReady = new Promise<void>((resolve) => reveal.on("pdf-ready", resolve));
      await core.render(deck.markdown, {
        resolve,
        reveal: {
          hash: false,
          postMessage: false,
          postMessageEvents: false,
          scrollActivationWidth: null,
          view: options.print ? "print" : "slide",
          controls: !options.clean,
          progress: !options.clean,
          pdfSeparateFragments: false,
          showNotes: false,
        },
      });
      initialized = true;
      reveal.on("slidechanged", () => send("slide", metadata()));
      if (options.slide === undefined && options.hash) {
        const match = options.hash.match(/^#\/(\d+)(?:\/(\d+))?/);
        if (match) reveal.slide(Number(match[1]), Number(match[2] ?? 0));
      }
    } else await core.reload(deck.markdown, { resolve });
    if (options.slide !== undefined) {
      const slides = reveal.getSlides();
      const n = Math.max(1, Math.min(slides.length, options.slide || 1));
      const index = reveal.getIndices(slides[n - 1]);
      reveal.slide(index.h, index.v ?? 0);
    }
    oldUrls.forEach((url) => URL.revokeObjectURL(url));
    await printReady;
    await Promise.race([
      settle(),
      interrupted,
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("Timed out waiting for slide assets.")), 20000),
      ),
    ]);
    reveal.layout();
    if (activeGeneration === latestGeneration)
      send("ready", { ...metadata(), height: document.documentElement.scrollHeight });
  }
  window.addEventListener("message", async (event) => {
    if (event.source !== parent || !event.data || typeof event.data.channel !== "string") return;
    const message = event.data;
    if (channel && channel !== message.channel) return;
    channel = message.channel;
    if (message.type === "load" && Number.isInteger(message.generation)) {
      latestGeneration = message.generation;
      pending = message;
      interrupt?.();
      if (busy) return;
      busy = true;
      while (pending) {
        const request = pending;
        pending = undefined;
        activeGeneration = request.generation;
        try {
          await load(request.deck, request.options);
        } catch (error) {
          if (activeGeneration === latestGeneration)
            send("error", {
              message: error instanceof Error ? error.message : "Could not render deck.",
            });
        }
      }
      interrupt = undefined;
      busy = false;
    } else if (initialized && message.type === "overview") reveal.toggleOverview();
    else if (
      initialized &&
      message.type === "navigate" &&
      Number.isInteger(message.h) &&
      Number.isInteger(message.v)
    )
      reveal.slide(message.h, message.v);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key.toLowerCase() === "m") send("menu");
    if (event.key.toLowerCase() === "s") send("notes", metadata());
    if (event.key.toLowerCase() === "f") send("fullscreen");
  });
}
