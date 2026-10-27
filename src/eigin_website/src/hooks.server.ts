import { isLocale } from "#lib/locales.ts";
import type { Handle } from "@sveltejs/kit/hooks";

/** Set the document language in prerendered HTML, before hydration. */
export const handle: Handle = async ({ event, resolve }) =>
  resolve(event, {
    transformPageChunk: ({ html }) =>
      html.replace("%lang%", isLocale(event.params.lang) ? event.params.lang : "en"),
  });
