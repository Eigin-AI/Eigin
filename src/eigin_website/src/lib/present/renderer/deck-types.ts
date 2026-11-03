/** Reveal methods used to compose and update deck content inside the iframe. */
export interface DeckReveal {
  getSlides(): (HTMLElement & { slideBackgroundElement?: HTMLElement })[];
  getIndices(): { h: number; v?: number };
  initialize(options: Record<string, unknown>): Promise<void>;
  getPlugin(name: "markdown"): { init(reveal: DeckReveal): Promise<void> };
  getPlugin(name: "highlight"): { init?(reveal: DeckReveal): void } | undefined;
  sync(): void;
  slide(h: number, v: number): void;
}

/** Content resolution and optional Reveal configuration for a deck render. */
export interface DeckOptions {
  resolve?: (reference: string) => string | null;
  reveal?: Record<string, unknown>;
  onReady?: () => void;
}

/** Renderer API installed in the isolated frame. */
export interface DeckRenderer {
  render(markdown: string, options?: DeckOptions): Promise<void>;
  reload(markdown: string, options?: DeckOptions): Promise<void>;
  rewriteMedia(markdown: string, resolve?: DeckOptions["resolve"]): string;
  applyThemeBackgrounds(): void;
}

/** Bundled globals belong to the slide iframe, not the parent website. */
export interface DeckGlobals {
  Reveal: DeckReveal;
  RevealMarkdown: unknown;
  RevealHighlight: unknown;
  RevealZoom: unknown;
  EiginArtwork: Record<string, string>;
  EiginPresent: DeckRenderer;
}
