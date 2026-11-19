import { publishedCalls } from "#lib/server/runtime.ts";
import type { PageServerLoad } from "./$types";
export const load: PageServerLoad = async ({ url }) => {
  const published = publishedCalls();

  return {
    calls: await published.open(),
    previous: await published.list(
      Number(url.searchParams.get("previousPage") ?? 1),
    ),
  };
};
