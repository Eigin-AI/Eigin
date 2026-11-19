import { error, redirect } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { reviewBrief } from "#lib/server/call.ts";
import type { PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ locals, params }) => {
  const { call } = await requireReviewCall(locals.user, params.slug);
  if (!reviewBrief(call.slug)) error(404, "Call brief unavailable");
  redirect(307, `/review/calls/${call.slug}`);
};
