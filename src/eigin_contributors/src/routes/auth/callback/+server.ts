import { redirect } from "@sveltejs/kit";
import { auth, origin } from "#lib/server/runtime.ts";
import type { RequestHandler } from "./$types";
export const GET: RequestHandler = async ({ cookies, url }) => {
  const binding = cookies.get("contributors_oauth");
  cookies.delete("contributors_oauth", { path: "/auth" });
  let destination = "/account";
  try {
    if (url.origin !== origin() || url.searchParams.has("error"))
      throw new Error("Login rejected");
    const login = await auth().complete(
      binding,
      url.searchParams.get("state"),
      url.searchParams.get("code"),
    );
    await auth().logout(cookies.get("contributors_session"));
    destination = login.returnTo;
    cookies.set("contributors_session", login.token, {
      path: "/",
      httpOnly: true,
      sameSite: "lax",
      secure: origin().startsWith("https:"),
      maxAge: 7 * 86400,
    });
  } catch {
    redirect(303, "/auth/problem");
  }
  redirect(303, destination);
};
