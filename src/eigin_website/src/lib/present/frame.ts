import reveal from "reveal.js/dist/reveal.js?raw";
import markdown from "reveal.js/plugin/markdown/markdown.js?raw";
import highlight from "reveal.js/plugin/highlight/highlight.js?raw";
import zoom from "reveal.js/plugin/zoom/zoom.js?raw";
import resetCss from "reveal.js/dist/reset.css?inline";
import revealCss from "reveal.js/dist/reveal.css?inline";
import highlightCss from "reveal.js/plugin/highlight/monokai.css?inline";
import theme from "./renderer/theme.css?inline";
// Bundle the deck renderer as source for the nonce-restricted iframe.
import deckRenderer from "./renderer/deck-renderer.js?raw";
import { rendererRuntime } from "./renderer/runtime";
import type { Deck } from "./sources";
import { artwork as icons } from "./artwork";

const fonts = import.meta.glob(
  "../../../../../design/assets/fonts/{FiveSerifText,NorthEast}/*-{Light,Regular,Medium,DemiBold,Bold,ExtraBold}{, copy}.otf",
  { query: "?inline", import: "default", eager: true },
) as Record<string, string>;
/** Inline complete artwork references, leaving absolute URLs and code examples unchanged. */
export function inlineArtwork(text: string, css = false): string {
  const resolve = (ref: string) =>
    icons[ref]
      ? "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(icons[ref])))
      : ref;
  const styles = (value: string) =>
    value.replace(
      /url\(\s*(["']?)([^"')]+)\1\s*\)/gi,
      (_match, _quote: string, ref: string) => `url("${resolve(ref.trim())}")`,
    );
  if (css) return styles(text);
  return text.replace(
    /(```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`|<style\b[^>]*>[\s\S]*?<\/style>|<[^>]+>|!\[[^\]]*\]\([^)]*\))/gi,
    (token) => {
      if (token.startsWith("`") || token.startsWith("~~~")) return token;
      if (/^<style\b/i.test(token)) return styles(token);
      if (token.startsWith("!"))
        return token.replace(
          /(!\[[^\]]*\]\()([^\s)]+)/,
          (_m, prefix: string, ref: string) => prefix + resolve(ref),
        );
      return token
        .replace(
          /(\b(?:src|data-background-image)=["'])([^"']+)(["'])/gi,
          (_m, prefix: string, ref: string, suffix: string) => prefix + resolve(ref) + suffix,
        )
        .replace(
          /(\bstyle=)(["'])([\s\S]*?)\2/gi,
          (_m, prefix: string, quote: string, value: string) =>
            prefix +
            quote +
            styles(value).replaceAll(quote, quote === '"' ? "&quot;" : "&#39;") +
            quote,
        );
    },
  );
}

function fontCss(): string {
  const weights: Record<string, number> = {
    Light: 300,
    Regular: 400,
    Medium: 500,
    DemiBold: 600,
    Bold: 700,
    ExtraBold: 800,
  };
  return Object.entries(fonts)
    .flatMap(([path, url]) => {
      const match = path.match(
        /(FiveSerifText|NorthEastCN)-(Light|Regular|Medium|DemiBold|Bold|ExtraBold)(?: copy)?\.otf$/,
      );
      const features = match?.[1] === "NorthEastCN" ? 'font-feature-settings:"ss01" 1;' : "";
      return match
        ? [
            `@font-face{font-family:'${match[1]}';src:url('${url}');font-weight:${weights[match[2]]};font-display:block;${features}}`,
          ]
        : [];
    })
    .join("\n");
}

/** Build a self-contained, nonce-restricted renderer document. Decks are sent later as data. */
export function frameDocument(): string {
  const nonce = crypto.randomUUID();
  const artwork = Object.fromEntries(
    Object.entries(icons)
      .filter(([path]) => path.includes("/illustration/"))
      .map(([path, svg]) => [
        path.split("/").pop()!.replace(".svg", ""),
        "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svg))),
      ]),
  );
  const script = [
    reveal,
    markdown,
    highlight,
    zoom,
    `window.EiginArtwork=${JSON.stringify(artwork)};`,
    deckRenderer,
    `(${rendererRuntime.toString()})()`,
  ]
    .join(";\n")
    .replace(/<\/script/gi, "<\\/script");
  const css = [
    resetCss,
    revealCss,
    highlightCss,
    fontCss(),
    inlineArtwork(theme, true),
    "html,body{margin:0;width:100%;height:100%;background:#232323} .reveal .speaker-notes{display:none!important}",
  ]
    .join("\n")
    .replace(/<\/style/gi, "<\\/style");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="robots" content="noindex,nofollow"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; img-src https: http: data: blob:; media-src https: http: data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'none'"><base href="${location.origin}/"><title>Presentation</title><style>${css}</style></head><body><div class="reveal"><div class="slides"></div></div><script nonce="${nonce}">${script}</script></body></html>`;
}

/** Prepare supported root artwork paths before crossing the frame boundary. */
export function frameDeck(deck: Deck): Deck {
  return { ...deck, markdown: inlineArtwork(deck.markdown) };
}
