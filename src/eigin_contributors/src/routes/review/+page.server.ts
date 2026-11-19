import { requireReviewer } from "#lib/server/review-access.ts";
import { availableCall, reviewCalls } from "#lib/server/call.ts";
import { review } from "#lib/server/runtime.ts";
import type { PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ locals }) => {
  const user = requireReviewer(locals.user);
  return {
    calls: (await review().calls(user, reviewCalls())).filter((call) =>
      availableCall(call.slug),
    ),
  };
};
