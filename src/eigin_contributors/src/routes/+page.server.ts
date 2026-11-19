import { dev } from "$app/env";
import { publishedCalls } from "#lib/server/runtime.ts";
import type { PageServerLoad } from "./$types";
export const load: PageServerLoad = async ({ url }) => {
  if (!dev)
    return { calls: [], previous: { entries: [], page: 1, hasNext: false } };
  const published = publishedCalls();

  return {
    calls: await published.open(),
    previous: await published.list(
      Number(url.searchParams.get("previousPage") ?? 1),
    ),
  };
};
