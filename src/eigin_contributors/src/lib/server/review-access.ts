import { error } from "@sveltejs/kit";
import { reviewCalls } from "./call.ts";
import { canReview, review } from "./runtime.ts";
import type { User } from "./auth.ts";

/** Call in every reviewer loader and download handler, including child routes. */
export function requireReviewer(user: User | null): User {
  if (!canReview(user)) error(404, "Not found");
  return user;
}

/** Resolve only a configured or persisted call, after checking reviewer access. */
export async function requireReviewCall(user: User | null, slug: string) {
  const reviewer = requireReviewer(user);
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) error(404, "Not found");
  const [call] = await review().calls(reviewer, reviewCalls(), { slug });
  if (!call) error(404, "Not found");
  return { user: reviewer, call };
}
