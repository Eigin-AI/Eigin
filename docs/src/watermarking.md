# Watermarking

Eigin applies a best-effort, invisible watermark to assistant-written text when
it leaves the app. It marks output as Eigin-generated so an unassuming copy or
sent email can be attributed back to Eigin.

## Why

The EU AI Act (Article 50(2)) asks a provider of a system that generates
synthetic text to mark outputs as machine-readable and detectable — but only
"as far as technically feasible", weighing cost and the state of the art.

Eigin does not run the models, so generation-time watermarking (token sampling)
is not available, and post-hoc paraphrase watermarking is slow and expensive.
A lightweight post-hoc mark is the feasible, honest option for an app layer.

We are honest about the limits. The mark is **not robust**: a technical user
can strip it, and re-typing or paraphrasing destroys it. That is within the
Act's feasibility standard for text, stated plainly.

## Where it applies

The watermark is appended at egress only — the stored conversation stays clean,
so the mark is never fed back to the model and never affects editing.

- Full-message **copy** to the clipboard.
- Agent **email send / reply**.

Partial/selection copy is out of scope. Code is untouched because the mark is
appended after all content.

## Encoding scheme (the contract)

This is a cross-language contract: the on-device Swift encoder and the CLI's
Rust detector must agree exactly.

| Symbol   | Code point | Meaning              |
| -------- | ---------- | -------------------- |
| `0`      | U+200B     | zero-width space     |
| `1`      | U+200C     | zero-width non-joiner |
| sentinel | U+2060     | word joiner (frame)  |

- Payload = `version` (u8) followed by `magic` (u16), 24 bits, most-significant
  first.
- Canonical Eigin signature: `version = 1`, `magic = 0xE191`.
- Marker token = `sentinel` + 24 payload bits + `sentinel`.
- Placement: one marker token appended at the very end of the message.

Detection scans for `sentinel .. sentinel` frames enclosing exactly 24 `0`/`1`
characters, decodes the payload, and validates `magic` against the canonical
value.

Known gap: some paste targets trim trailing invisible characters, dropping the
mark. Acceptable for the full-message-copy scope.

## Enablement

Watermarking is controlled by build config, not a user setting. The signature
is defined once in `config/app.toml` (`[watermark] signature`, hex e.g. `E191`),
rendered into the iOS build as the `EiginWatermarkSignature` Info.plist value and
stamped into the mark. Empty, missing, or unparseable disables watermarking (the
encoder becomes a no-op). The value must match the detector's canonical magic
(`0xE191`) to be detectable. There is no user-facing toggle.

## Detecting

The Rust CLI reports whether text carries the Eigin mark:

```
eigin watermark detect <file>   # or "-" for stdin
```

Exit codes: `0` = watermarked, `1` = not watermarked, `2` = read error. Shared
test vectors live in `tools/src/watermark/vectors.json`; both the Rust and Swift
test suites check against them so the two implementations cannot drift.
