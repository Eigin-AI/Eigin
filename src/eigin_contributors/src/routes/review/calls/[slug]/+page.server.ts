import { requireReviewCall } from "#lib/server/review-access.ts";
import { reviewBrief } from "#lib/server/call.ts";
import type { PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ locals, params }) => {
  const { call } = await requireReviewCall(locals.user, params.slug);
  return { brief: reviewBrief(call.slug) ?? null };
};
