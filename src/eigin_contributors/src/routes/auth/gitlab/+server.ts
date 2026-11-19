import { error, redirect } from "@sveltejs/kit";
import { auth, origin } from "#lib/server/runtime.ts";
import { signInLimit } from "#lib/server/sign-in-limit.ts";
import type { RequestHandler } from "./$types";
const retryAfter = signInLimit();
export const GET: RequestHandler = async ({
  cookies,
  url,
  getClientAddress,
}) => {
  const retryIn = retryAfter(getClientAddress());
  if (retryIn)
    return new Response("Too many sign-in attempts. Try again shortly.", {
      status: 429,
      headers: { "Retry-After": String(retryIn) },
    });
  let location: string;
  try {
    if (url.origin !== origin())
      error(400, "Use the configured portal address to sign in.");
    const attempt = await auth().begin(url.searchParams.get("returnTo"));
    cookies.set("contributors_oauth", attempt.binding, {
      path: "/auth",
      httpOnly: true,
      sameSite: "lax",
      secure: origin().startsWith("https:"),
      maxAge: 600,
    });
    location = attempt.url;
  } catch {
    error(503, "Sign-in is not configured or is temporarily unavailable.");
  }
  redirect(303, location, { external: ["https://code.eigin.ai"] });
};
