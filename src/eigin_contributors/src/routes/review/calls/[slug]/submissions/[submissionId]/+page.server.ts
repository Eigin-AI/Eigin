import { error } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { review } from "#lib/server/runtime.ts";
import type { PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ locals, params }) => {
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  const selected = await review().detail(user, call.slug, params.submissionId);
  if (!selected) error(404, "Not found");
  return { selected };
};
