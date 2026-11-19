## The problem

Eigin agents search the web, fetch pages, and access external services through MCP. Responses can contain malicious instructions that redirect the agent to expose private information or trigger unwanted actions.

Today, these tools ask for permission by default. We want to reduce that friction for tools known to be read-only by detecting malicious instructions before their responses enter the agent's context.

## What we are asking for

Propose a local approach to detecting malicious instructions in external tool responses. Heuristics, small models, or a combination are all welcome.

The goal is to confidently pass a useful share of benign responses while retaining approval for uncertain cases.

## Constraints

The solution must meet these to fit into Eigin.

<!-- foldouts -->

### Local-first

Runs on the device without round-tripping a hosted model or service.

### Cross-platform

Ready for implementation in Eigin's Rust SDK, which has Swift and WebAssembly bindings. You do not need to implement the bindings.

### Small distribution

Smaller is better. Code alone is ideal. Allow at most 100 MB of additional assets, including models, tokenizers, and runtime dependencies. Bundling assets is preferable. On-demand download is also an option.

### Small footprint

Consider an iPhone 15 already running a local LLM and speech model, potentially consuming several GB of memory. Keep additional baseline and peak memory use low, along with cold and warm execution latency.

### Multiple languages

Our initial focus is Danish and English. Design for mixed-language content and explain how support could extend to more languages.

### Conservative fallback

If screening is unavailable, fails, takes too long, or is uncertain, retain the existing approval requirement.

### Permissive licensing

Any external assets or libraries must use permissive licenses compatible with Eigin's license.

<!-- end-foldouts -->

## Boundaries and permissions

Screening should happen after a tool runs and before its response enters the agent's context. Explain how screening fits with permission checks before execution and what the user needs to do when screening is uncertain. Screening must not grant permission for destructive actions.

## What we look for in a spec

- **Threat model:** which attacks your design addresses and which are out of scope.
- **Approach:** how it works and why you chose it.
- **Integration:** how it fits the SDK, tool permissions, and agent context.
- **Evaluation:** how you would measure missed attacks, unnecessary prompts, language support, and device performance.
- **Failure modes:** where it can go wrong and how it falls back safely.
- **Delivery:** a high-level implementation plan and a useful first experiment.

We value a practical design with clear trade-offs and evidence for its claims. A working product is not required. Small experiments, reproducible tests, or measurements are useful when they support the spec.

## Code and context

We’re migrating Eigin's agent runtime from the iOS app to our cross-platform Rust SDK. We expect to implement this capability in the SDK. These links show how we handle permissions and tool responses today:

- [Tool permission model](https://docs.eigin.ai/tools/permissions.html)
- [Privacy and prompt-injection guidance](https://docs.eigin.ai/privacy.html)
- [Web search permission default](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_ios/Sources/Agent/Web/Tools/WebSearchTool.swift)
- [Web page fetching and response handling](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_ios/Sources/Agent/Web/Tools/WebFetchTool.swift)
- [Permission resolution](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_ios/Sources/Core/Tools/ToolPermission.swift)
- [Tool execution and conversation history](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_ios/Sources/Chat/Services/AgenticChatLoop.swift)

## Participation

When this call closes, we’ll select one spec and one runner-up to receive funding.

This call accepts individual contributions. To submit, you’ll need to accept our [Individual CLA](https://docs.eigin.ai/contributing/individual-agreement.html) and [participation terms](/guides/participation-terms).
