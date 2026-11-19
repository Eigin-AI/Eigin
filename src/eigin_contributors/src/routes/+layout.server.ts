import type { LayoutServerLoad } from "./$types";
import { canReview } from "#lib/server/runtime.ts";
export const load: LayoutServerLoad = ({ locals }) => ({
  user: locals.user,
  canReview: canReview(locals.user),
});
