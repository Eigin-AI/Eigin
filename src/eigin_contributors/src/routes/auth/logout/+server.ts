import { error, redirect } from "@sveltejs/kit";
import { auth, origin } from "#lib/server/runtime.ts";
import type { RequestHandler } from "./$types";
export const POST: RequestHandler = async ({ cookies, request }) => {
  if (request.headers.get("origin") !== origin())
    error(403, "Invalid request origin.");
  try {
    await auth().logout(cookies.get("contributors_session"));
  } catch {
    error(503, "Sign-out could not be completed. Please try again.");
  }
  cookies.delete("contributors_session", { path: "/" });
  cookies.delete("contributors_oauth", { path: "/auth" });
  redirect(303, "/");
};
