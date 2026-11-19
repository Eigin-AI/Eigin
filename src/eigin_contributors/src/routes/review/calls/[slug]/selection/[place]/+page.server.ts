import { error } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { selection } from "#lib/server/runtime.ts";
import type { PageServerLoad } from "./$types";
export const load: PageServerLoad = async ({ locals, params }) => {
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  if (params.place !== "selected" && params.place !== "runner-up")
    error(404, "Not found");
  const awarded = await selection().awarded(user, call.slug, params.place);
  if (!awarded) error(404, "Not found");
  return { awarded, place: params.place };
};
