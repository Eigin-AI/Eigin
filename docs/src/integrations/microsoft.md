# Microsoft

Provides the `email` capability via the Microsoft Graph API: list, search, read, send, and reply. Personal accounts only — Hotmail, outlook.com, and live.dk. Work/school (Microsoft 365) accounts aren't supported.

## Requirements

| Requirement | Notes |
|---|---|
| Azure app registration, **personal Microsoft accounts only** | Authorizes against the `/consumers` authority. Requests `Mail.Read`, `Mail.Send`, `offline_access`, `User.Read` delegated permissions. |
| Platform: **Mobile and desktop applications** | Public client, no secret. Redirect URI is `msauth.<bundle-id>://auth` — register one per Bundle ID (dev and production need separate entries, and separate app registrations if their Bundle IDs differ). |
| `EIGIN_MICROSOFT_OAUTH_CLIENT_ID_STAGING` / `_PRODUCTION` | Set in `.env` (see `.env.example`), wired into the app via `EiginMicrosoftOAuthClientID` in `Info.plist`. Connecting Microsoft fails fast with a clear error if this is missing. |
| Setup process | Manual only, through the [Azure Portal app registrations](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) — there's no API for creating this kind of registration, so it can't be codified. |

## Partial consent

Like Google, Microsoft's consent screen lets scopes be approved individually. Denying one still connects the account, but Eigin only exposes tools for what was actually granted.

## Known limitations

- **Search syntax**: `search_emails`' query is forwarded verbatim to Graph's `$search` query parameter, which uses [Keyword Query Language](https://learn.microsoft.com/en-us/graph/search-query-parameter) rather than Gmail's `q` operators (e.g. `from:`, `subject:`) — the same tool call means something different depending on which provider is connected.
- **Sending has no real id**: Graph's `sendMail`/`reply` actions send immediately and return no body, so there's nothing to read back. Eigin synthesizes the returned message from what was submitted instead — the agent still sees the subject/body it committed to, but the message's id is empty rather than a real one, so it can't be looked up again with `read_email`. This keeps the integration on the same read/send-only grant as Gmail (`Mail.Read`/`Mail.Send`) rather than requesting `Mail.ReadWrite`, which also grants deleting and moving mail.
