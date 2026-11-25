# Knowledge

The SDK loads structured knowledge, finds relevant entries, and prepares edits. See [agent knowledge](../agents/knowledge.md) for entity types and agent tools.

The API is experimental: `EiginSDK.Experimental.Knowledge` on Apple and exports from `@eigin/sdk` in browsers.

## Load and query

Supply authorized schemas and source records to build an immutable workspace. Use entity lookup for known IDs, relationships for connected entries, and Firm queries for filtering. Your host owns authorization and storage.

## Find relevant entries

Pass entities, embedding vectors, and memory metadata to scoring, then rank with a threshold and limit. The host generates embeddings. Exact identities outrank incidental mentions; usage and importance reorder close matches.

## Save changes

1. Prepare a validated candidate with `replacingSource` or `removingSource`.
2. Save the record changes in host storage.
3. Publish the candidate after success.

Serialize this sequence or reject stale candidates. Failed edits leave the committed workspace usable.

For typed edits, `generateEntityDsl(entity, source.path)` returns source text. The logical path preserves relative paths in fields; the host chooses its storage location. Unsupported values return typed errors.

Schedule workspace construction off the UI thread. See [SDK setup](../../../src/eigin_sdk/README.md) for prerequisites and commands.
