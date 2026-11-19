import { createHash, randomBytes } from "node:crypto";
import type { Pool } from "pg";

export type User = {
  id: string;
  gitlabId: string;
  username: string;
  name: string;
  authorEmail?: string | null;
};
export type AuthConfig = {
  origin: string;
  clientId: string;
  clientSecret: string;
};
export class AuthFailure extends Error {}
const provider = "https://code.eigin.ai";
const randomToken = () => randomBytes(32).toString("base64url");
const hash = (value: string) =>
  createHash("sha256").update(value).digest("hex");
const validToken = (value: string | undefined): value is string =>
  !!value && /^[A-Za-z0-9_-]{43}$/.test(value);

/** Retain supported same-origin page destinations across sign-in. */
export function safeReturnTo(value: string | null | undefined) {
  if (
    !value ||
    !value.startsWith("/") ||
    value.startsWith("//") ||
    value.length > 2048 ||
    /[\s\\\x00-\x1f\x7f]/.test(value)
  )
    return "/";
  const parsed = new URL(value, "https://portal.invalid");
  if (parsed.origin !== "https://portal.invalid") return "/";
  const page = parsed.pathname;
  const allowed =
    page === "/" ||
    page === "/account" ||
    /^\/guides\/(spec|example|process|terms|participation-terms)$/.test(page) ||
    /^\/calls\/[a-z0-9]+(?:-[a-z0-9]+)*(?:\/submission|\/specs\/(selected|runner-up))?$/.test(
      page,
    ) ||
    /^\/review(?:\/calls\/[a-z0-9]+(?:-[a-z0-9]+)*(?:\/selection(?:\/(?:selected|runner-up))?|\/submissions\/[1-9]\d*)?)?$/.test(
      page,
    );
  return allowed ? parsed.pathname + parsed.search + parsed.hash : "/";
}

/** Single-provider OAuth and opaque PostgreSQL sessions. */
export class Auth {
  private pool: Pool;
  private config: AuthConfig;
  private request: typeof fetch;
  constructor(pool: Pool, config: AuthConfig, request: typeof fetch = fetch) {
    this.pool = pool;
    this.config = config;
    this.request = request;
  }

  async begin(returnTo?: string | null) {
    const binding = randomToken();
    const state = randomToken();
    const verifier = randomToken();
    await this.pool.query(
      "INSERT INTO oauth_attempts (binding_hash,state_hash,verifier,expires_at,return_to) VALUES ($1, $2, $3, clock_timestamp() + interval '10 minutes', $4)",
      [hash(binding), hash(state), verifier, safeReturnTo(returnTo)],
    );
    const url = new URL("/oauth/authorize", provider);
    url.search = new URLSearchParams({
      client_id: this.config.clientId,
      redirect_uri: `${this.config.origin}/auth/callback`,
      response_type: "code",
      scope: "read_user",
      state,
      code_challenge: createHash("sha256").update(verifier).digest("base64url"),
      code_challenge_method: "S256",
    }).toString();
    return { binding, url: url.toString() };
  }

  async complete(
    binding: string | undefined,
    state: string | null,
    code: string | null,
  ) {
    if (
      !validToken(binding) ||
      !validToken(state ?? undefined) ||
      !code ||
      code.length > 4096
    )
      throw new AuthFailure("Invalid callback");
    // Consume before contacting GitLab: callback retries cannot replay the authorization.
    const attempt = await this.pool.query(
      "DELETE FROM oauth_attempts WHERE binding_hash = $1 AND state_hash = $2 AND expires_at > clock_timestamp() RETURNING verifier, return_to",
      [hash(binding), hash(state!)],
    );
    if (!attempt.rowCount) throw new AuthFailure("Expired or invalid callback");
    const tokenResponse = await this.request(`${provider}/oauth/token`, {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(10000),
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        code,
        redirect_uri: `${this.config.origin}/auth/callback`,
        code_verifier: attempt.rows[0].verifier,
      }),
    });
    if (!tokenResponse.ok) throw new AuthFailure("Provider rejected login");
    const token = await tokenResponse.json();
    if (
      typeof token.access_token !== "string" ||
      !token.access_token ||
      token.access_token.length > 8192
    )
      throw new AuthFailure("Invalid provider response");
    const response = await this.request(`${provider}/api/v4/user`, {
      headers: { Authorization: `Bearer ${token.access_token}` },
      redirect: "error",
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new AuthFailure("Identity lookup failed");
    const profile = await response.json();
    if (
      !Number.isSafeInteger(profile.id) ||
      profile.id <= 0 ||
      typeof profile.username !== "string" ||
      !profile.username ||
      profile.username.length > 255 ||
      typeof profile.name !== "string" ||
      profile.name.length > 255
    )
      throw new AuthFailure("Invalid identity");
    const validEmail = (value: unknown): value is string =>
      typeof value === "string" &&
      value.length <= 254 &&
      /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
    // Never invent a private commit address or substitute the account's private contact email.
    const authorEmail =
      profile.commit_email === "_private"
        ? null
        : validEmail(profile.commit_email)
          ? profile.commit_email
          : validEmail(profile.public_email)
            ? profile.public_email
            : null;
    const session = randomToken();
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const user = await client.query(
        "INSERT INTO users (gitlab_user_id, gitlab_username, display_name, author_email) VALUES ($1,$2,$3,$4) ON CONFLICT (gitlab_user_id) DO UPDATE SET gitlab_username = EXCLUDED.gitlab_username, display_name = EXCLUDED.display_name, author_email = EXCLUDED.author_email RETURNING id",
        [profile.id, profile.username, profile.name, authorEmail],
      );
      await client.query(
        "INSERT INTO sessions VALUES ($1,$2,clock_timestamp() + interval '7 days')",
        [hash(session), user.rows[0].id],
      );
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
    return {
      token: session,
      returnTo: safeReturnTo(attempt.rows[0].return_to),
    };
  }

  async user(session: string | undefined): Promise<User | null> {
    if (!validToken(session)) return null;
    const result = await this.pool.query(
      "SELECT u.id, u.gitlab_user_id, u.gitlab_username, u.display_name, u.author_email FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = $1 AND s.expires_at > clock_timestamp()",
      [hash(session)],
    );
    const row = result.rows[0];
    return row
      ? {
          id: row.id,
          gitlabId: row.gitlab_user_id,
          username: row.gitlab_username,
          name: row.display_name,
          authorEmail: row.author_email,
        }
      : null;
  }

  async logout(session: string | undefined) {
    if (validToken(session))
      await this.pool.query("DELETE FROM sessions WHERE token_hash = $1", [
        hash(session),
      ]);
  }
}
