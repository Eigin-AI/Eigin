import social from "#lib/content/social.json";

export const prerender = true;
export const trailingSlash = "never";

/** Allow crawling and advertise the generated sitemap. */
export function GET() {
  return new Response(`User-agent: *\nAllow: /\n\nSitemap: ${social.origin}/sitemap.xml\n`, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
