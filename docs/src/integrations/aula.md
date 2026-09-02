# Aula

[Aula](https://aula.dk) is the Danish school and daycare communication platform. This integration gives the agent read-only access to a connected Aula account: a digest of what's happening with the user's children, message threads, and the calendar.

**This is an unofficial API client.** Aula (by Netcompany / Kombit) has not published a public API or an integration story, so this talks to the same undocumented JSON API the community's reverse-engineered clients use. We haven't seen a statement from Aula, Kombit, or Netcompany for or against this kind of use, though it's known to exist in other personal and commercial AI products. If the rights holders ask us to stop, we will.

## Tools

| Tool | What it does |
|---|---|
| `aula_updates` | A digest of unread/recent messages, notifications, upcoming calendar events, and recent posts in one call. |
| `aula_children` | The user's children and which school/daycare each attends. Captured at connect time, so it needs no network call. |
| `aula_messages_list` / `aula_message_read` | Scan message threads, then read one in full by id. |
| `aula_calendar` | Events for a date range. |

## How it works

Aula's own security model is strict: every login goes through the user's official ID, not an API key or a lightweight OAuth consent screen. Three things are involved:

| Entity | Role |
|---|---|
| **MitID** | Denmark's national digital identity, the same login used for banking, tax, and health records. This is where the user proves who they are. |
| **UniLogin (broker)** | An identity layer Danish municipal systems (like Aula) sit behind. It's the thing that talks to MitID and vouches for the result back to Aula. |
| **Aula** | Only ever sees the outcome: a signed assertion that says "yes, this is a verified guardian," followed by the app's own JSON API. |

We don't reimplement MitID itself - that's not something a third party should be trusted with. What we do take over programmatically, following the approach community-built API clients have already worked out, is the broker's tail end *after* MitID has already vouched for the user: plain redirect and form hand-offs that need no further input from them:

1. We open Aula's real login page in an embedded, interactive web view and let the user complete the actual MitID login exactly as they would in a browser, including the hand-off to the MitID app if they use that.
2. Once MitID succeeds, the broker hands back a chain of redirects toward Aula. The last leg of that chain needs no further user input, so we take over there and finish it programmatically rather than in the visible web view.
3. That leg ends with Aula handing back a code we exchange for an access token. A token is required: a leg that only lands on the logged-in site with browser cookies but no code is treated as a failed sign-in, because a cookie-only session can't be re-established once those cookies lapse.
4. From then on, the access token is the credential every API call carries, the same way Aula's own web app talks to its API; the short-lived web cookies are re-primed from it as needed.

The web cookies (from logged-in browser session) are disposable: they lapse after about a day, independently of the token. When they lapse, we don't need the user to log in again - we re-establish the web session from the token by re-priming it in the background, the same way the app's own client does after an idle period. An interactive reconnect is only needed when the refresh token itself dies, which is something a background step can't recover.

That interactive reconnect is in-place: the integration's detail screen has a **Reconnect** action that re-runs this same WKWebView login under the existing integration id, so nothing referencing the connection (capability selections, permissions) is replaced — the user just logs in again over the old connection.

The technical details are documented inline in the integration code.

### Configuration

| Requirement | Notes |
|---|---|
| `EIGIN_AULA_OAUTH_CLIENT_ID` | Aula's own mobile-app OAuth client id, sourced from [aula-mcp](https://github.com/Casperjuel/aula-mcp). Committed in `config/app.toml`. Wired into the app via `EiginAulaOAuthClientID` in `Info.plist`. Connecting Aula fails fast with a clear error if it's missing. |

## Status and known limitations

This is an experimental integration. A little out of the ordinary compared to our other integrations, since it rides on an unofficial API. We expect Aula's API to drift over time and will need to keep an eye on it; for now we're rolling with it and seeing how it goes.

Third-party homework/weekly-plan providers (MinUddannelse, Meebook, EasyIQ, Huskelisten) aren't included in this first implementation.
