# IMAP

Provides the `email` capability via plain IMAP/SMTP: list, search, read, send, and reply. This is the catch-all provider for accounts that aren't reachable through the Google or Microsoft OAuth integrations — iCloud, Fastmail, most self-hosted or ISP mailboxes, and encrypted providers like Proton (via [Proton Bridge](https://proton.me/mail/bridge), which runs a local IMAP/SMTP server for the app to talk to).

## Setup

Unlike Google and Microsoft, there's no redirect-based authorization flow — the user enters server settings directly:

- Email address
- Password (often an **app-specific password** rather than the account's normal password — required by iCloud, and recommended by most other providers when a third-party client authenticates directly)
- IMAP host + port (defaults to 993)
- SMTP host + port (defaults to 587)
- Optional separate IMAP/SMTP usernames, defaulting to the email address if left blank (iCloud, for example, accepts a separate "mail name" for IMAP login)

On submit, Eigin connects to *both* the IMAP and SMTP servers and authenticates before saving — this is IMAP's equivalent of the OAuth flows' token exchange proving the credentials work, and catches a broken send path (e.g. wrong SMTP username) before the integration is saved rather than on the agent's first send attempt.

### iCloud example

Apple's [Mail server settings for other email apps](https://support.apple.com/da-dk/102525) guide gives:

| | Host | Port | Username | Password |
|---|---|---|---|---|
| IMAP | `imap.mail.me.com` | 993 | iCloud mail name (or full address) | App-specific password |
| SMTP | `smtp.mail.me.com` | 587 | Full iCloud email address | Same app-specific password |

## Implementation

Built on [SwiftMail](https://github.com/Cocoanetics/SwiftMail) (BSD-2-Clause), which wraps IMAP and SMTP client protocol handling, MIME composition, and TLS on top of Apple's `swift-nio`/`swift-nio-ssl`/`swift-nio-imap`. Each tool call opens its own IMAP or SMTP connection, does the work, and disconnects — there's no long-lived connection to manage, mirroring how the OAuth providers fetch a token lazily per call rather than holding a session open.

## Known limitations

- **No native threading**: IMAP has no server-side thread concept like Gmail's `threadId` or Graph's `conversationId`. `threadID` is synthesized from the message's own `Message-ID` header (falling back to its UID), and replies set `In-Reply-To`/`References` from that — but a wider reply chain can't be reconstructed the way Gmail's real threading does.
- **INBOX only**: only the inbox is listed/searched; other folders (Sent, Archive, custom folders) aren't exposed.
- **Search**: `search_emails`' query maps to a single IMAP `TEXT` search criterion (subject, body, and headers) — there's no operator syntax like Gmail's `q` (`from:`, `subject:`, etc.) or Graph's KQL.
- **Plain text bodies preferred**: HTML-only messages have their tags stripped rather than rendered.
- **Sending has no real id**: like Microsoft, sent/reply messages aren't read back from the server — Eigin synthesizes the returned message from what was submitted, so its id is empty and it can't be looked up again with `read_email`.
