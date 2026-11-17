# Outgoing conversation preparation

The SDK turns history into request-ready messages: selecting retained history, repairing tool rounds, applying attachment retention, and placing prompts and hints.

The API is experimental: `eigin_sdk::conversation` in Rust and `EiginSDK.Experimental.Conversation` on Apple.

## Usage

1. Select the active conversation.
2. Gather hint text from the selected messages.
3. Prepare the request with the finished system prompt, hint, and model capability.

```swift
let selected = try EiginSDK.Experimental.Conversation.select(history)
// Gather hint text from selected.messages.
let outgoing = EiginSDK.Experimental.Conversation.prepare(
    selected,
    options: .init(
        systemPrompt: systemPrompt,
        systemHint: hint,
        supportsVision: supportsVision
    )
)
```

Rust uses `conversation_select` and `conversation_prepare` with the same inputs.

## Host contract

- The host owns prompt gathering, tools, context-budget decisions, storage, and persistence. Preparation produces outgoing copies; retain the original stored history.
- Messages carry unresolved attachment references. Load retained image bytes when converting to inference values.
- Prepared messages include source indices into the original history snapshot, allowing adapters to preserve local identity and metadata.
- Negative summary-retention counts return `ConversationPreparationError::InvalidRetainedCount`.
- For paging or loop hints on an assembled request, use `conversation_append_hint` or `Conversation.appendHint(_:to:)`. Supply nonempty text; the standalone helper appends even empty text, while full preparation skips empty hints.
