/** The host to show in a link warning: no scheme, no `www.`, no path. Empty
    where there is no host to name. */
export function linkHost(href: string): string {
  try {
    return new URL(href).host.replace(/^www\./, "");
  } catch {
    return "";
  }
}
