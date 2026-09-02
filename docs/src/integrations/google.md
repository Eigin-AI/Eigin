# Google

Provides the `email` capability via Gmail's REST API: list, search, read, send, and reply.

## Requirements

| Requirement | Notes |
|---|---|
| Gmail API + OAuth consent screen | Requests `gmail.readonly`, `gmail.send`, `userinfo.email`. The first two are restricted scopes — until the app is verified, only accounts added as **test users** can grant them. |
| OAuth 2.0 client, type **iOS** | One per Bundle ID (dev and production need separate clients). Redirect URI isn't configurable — Google fixes it to the reversed client ID, which Eigin computes automatically. Only set up for iOS today; expanding Eigin to another platform will need its own OAuth client, since Google's client types are platform-specific. |
| `EIGIN_GOOGLE_OAUTH_CLIENT_ID_STAGING` / `_PRODUCTION` | Committed in `config/app.toml`; a PKCE client id is public by design. Wired into the app via `EiginGoogleOAuthClientID` in `Info.plist`. Connecting Google fails fast with a clear error if this is missing. |
| Setup process | Manual only, through the [Google Cloud console](https://developers.google.com/identity/protocols/oauth2) — Google has no API for creating this kind of OAuth client, so it can't be codified. |

## Partial consent

Google's consent screen lets scopes be approved individually. Denying one still connects the account, but Eigin only exposes tools for what was actually granted — the connection detail screen shows which.
