import { dev } from "$app/env";
import { error } from "@sveltejs/kit";
import { publishedCalls } from "#lib/server/runtime.ts";
import type { PageServerLoad } from "./$types";
export const load: PageServerLoad = async ({ params }) => {
  if (!dev) error(404, "Not found");
  const spec = await publishedCalls().spec(params.slug, params.place);
  if (!spec) error(404, "Not found");
  return { spec, callSlug: params.slug };
};
