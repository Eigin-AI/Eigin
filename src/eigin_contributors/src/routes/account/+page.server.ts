import { dev } from "$app/env";
import { redirect } from "@sveltejs/kit";
import type { PageServerLoad } from "./$types";
export const load: PageServerLoad = ({ locals }) => {
  if (!locals.user) redirect(303, "/auth/gitlab");
  return { user: locals.user, canReadCalls: dev };
};
