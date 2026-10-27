# SDK migration plan

Status: working draft. This is a living record of the migration approach, decisions, and completed increments. Detailed designs belong in implementation issues, linked here as they are agreed.

- Design issue: [#145](https://code.eigin.ai/dev/eigin/-/issues/145)
- Milestone: [Eigin SDK](https://code.eigin.ai/dev/eigin/-/milestones/2)
- Related design: [#154 — Personal Agent Layout (PAL)](https://code.eigin.ai/dev/eigin/-/issues/154)

This document carries forward the incremental approach in the latest comment on #145. Earlier proposals remain research inputs; their full crate layouts, extraction sequences, storage choices, and frozen-build strategy are not commitments here.

## Destination

Move Eigin's agent harness from Swift into a cross-platform Rust SDK. Hosts supply configuration and platform capabilities; Rust owns agent behavior and orchestration.

The first consumers are iOS, web, and a Rust CLI. The CLI is a usable headless application and testing surface, with future support for personal agent workflows. Access to an existing agent's data and credentials needs its own design.

The longer-term frontends are SwiftUI on Apple platforms, Jetpack Compose on Android, and web/Tauri on Windows and Linux. Other applications can embed the SDK with their own adapters.

## Integration structure

Each UI host consumes a platform integration package over the SDK bindings:

```text
UI application
    → host integration package
        → language bindings
            → Rust SDK

Rust CLI application → Rust SDK
```

| Layer | Responsibility |
| --- | --- |
| Rust SDK | Agent behavior, orchestration, and platform-independent state. Defines interfaces for host-supplied capabilities. May contain multiple crates as real boundaries emerge. |
| Language bindings | Expose Rust operations and types to the host language with minimal handwritten behavior. UniFFI for Swift/Kotlin; verify the web mechanism separately, with `wasm-bindgen` as a candidate. |
| Host integration package | Adapt SDK concepts to the host runtime and provide reusable platform services. Independently testable from the UI application. |
| UI application | Presentation, composition, app-specific policy, and lifecycle integration. Configures and hosts the package, requests work, consumes state/events, and presents interactions. |

An Apple integration package, provisionally called `EiginKit`, can provide observable state, main-actor event delivery, subscription management, Swift-friendly errors, and platform adapters such as Keychain access. A corresponding web package provides browser-facing integration. Names and precise APIs remain open.

Applications still own entitlements, permission descriptions, background-task registration, lifecycle events, and system UI presentation. Integration packages expose hooks for these responsibilities and grow as extractions require them.

Keep generated bindings behind the integration package where practical. Test runtime adaptation and platform services independently of views.

## Migration approach

Extract one bounded responsibility at a time. Keep iOS shippable after every completed increment.

1. Inspect the implementation and callers; name behavior to preserve and deliberate changes.
2. Design a useful Rust interface and implement it with behavior tests.
3. Wire it into the actual iOS call path through bindings and the host package.
4. Verify affected app flows, headless use, and WASM compatibility (see verification below).
5. Delete replaced Swift code, record the outcome, and choose the next increment.

Move orchestration into Rust when its supporting components make that manageable. Prefer explicit inputs over SwiftData objects or app dependency containers. Keep temporary adapters small; reconsider scope if an extraction needs substantial compatibility machinery.

### Interfaces and retirement

The app-facing boundary moves upward as Rust takes on more responsibility. Initially the Swift loop calls a bound Rust provider; later it calls a Rust loop that uses the provider internally. The provider remains useful while its lower-level binding can be retired.

Early interfaces are provisional. Retire them visibly:

1. Deprecate the host-facing API with a message naming its replacement.
2. Build consumers to find remaining callers, migrate them, and verify behavior.
3. Remove the obsolete API and record it in the implementation log and relevant release notes.

Warnings must appear in the consuming language, on integration-package APIs and any directly exposed bindings. Verify generator support in a separate issue; Rust annotations alone may not produce Swift or TypeScript warnings.

Internal deprecation and removal may happen in one increment. External consumers require a versioning and removal-notice policy before we promise a stable public contract; our builds cannot reveal their remaining callers.

### State and persistence

Per-turn state can move before durable storage: buffers, tool-call accumulation, and execution progress need no database ownership. Value-based interfaces can remain useful after storage moves; context preparation can accept the same messages and budget regardless of where its caller loads them.

Aim for one coordinated user-data migration after clarifying Rust persistence and PAL ownership. This is a goal, not a guarantee. PAL covers agent definitions, overlays, and knowledge; its draft excludes chat transcripts. Settle those boundaries before choosing schemas or a storage engine.

## System map

This provisional map draws on the [system context](../src/system-context.md), [providers](../src/providers.md), [agent loop](../src/conversation/agentic-loop.md), and current code. Add missing domains and revise assessments as we learn. Rows describe responsibilities; they need not become crates or single extractions.

- **Independence:** how readily the portable part can run without unextracted Swift code.
- **App importance:** impact of failure on chat or a particular capability, rather than extraction priority.
- **Porting risk:** consequences and recovery difficulty. Small, independent code can still cause data loss or unauthorized actions.

| System / level | Independence | App importance | Porting risk and recovery |
| --- | --- | --- | --- |
| Parsing and context algorithms — low-level | High for parsing, token estimates, retention, and budget selection | High: malformed requests or poor context affect answers | Low–medium when operating on input values; higher when results overwrite stored history |
| Provider clients and networking — service | Medium–high; credentials, attachments, and app wiring remain dependencies | Core: selected inference paths depend on them | Medium: failed or incorrect requests, streaming, and cancellation; generally recoverable without a data migration |
| Prompt and context assembly — orchestration | Medium; rendering is separable, gathering agent/space/knowledge inputs is coupled | Core: determines what the agent knows and how it behaves | Medium–high: wrong context, scope leakage, or changed instructions; unsafe outputs may have downstream effects |
| Agent turn execution — high-level orchestration | Low today; coordinates providers, tools, model routing, checkpoints, and UI interaction | Core: conversation execution | High: broken turns, lost partial progress, duplicate actions, and inconsistent transcripts |
| Tools and permissions — policy plus orchestration | High for isolated policy evaluation; medium–low for execution and registry assembly | Core action and safety boundary | High: incorrect permission checks can authorize irreversible external actions, even if the policy code is small |
| Persistence and observation — cross-cutting foundation | Low today; SwiftData models and view consumption span the app | Core: history, settings, relationships, and visible state | High: data loss or incompatible schemas can survive rollback; observation failures can leave UI stale or inconsistent |
| Knowledge and agent definitions — data plus services | Medium; Firm is already Rust, while Swift coordinates storage, scope, and retrieval. PAL is a proposed design | High for memory and personalization | High for stored sources, identities, and scope; coordinate future PAL ownership before migrating data |
| Integrations — services and adapters | Medium; network protocols separate from OAuth presentation, secrets, and app capabilities | Capability-specific: connected services and their tools | High for external writes and access control; authentication failures can disconnect accounts |
| Local inference and voice — native adapters plus orchestration | Low for runtime/audio management; selected formatting and turn-taking logic can separate | Essential for local/offline or voice use | Medium–high: resource, timing, cancellation, and lifecycle failures; hardware and audio implementations remain native |
| Background activity — policy plus native scheduling | Medium for decision logic; low for OS scheduling and lifecycle | Capability-specific: proactive behavior | Medium–high: missed or duplicate work, notifications, and unattended actions; effects may persist outside the process |

Native facilities remain host implementations behind SDK-owned interfaces where needed.

## Initial increments

Swift retains the agent loop during these increments. Detailed scope and acceptance criteria belong in implementation issues.

### 1. SDK initialization across hosts

Set up the SDK with an async initialization function that reports success or failure. No agent behavior moves yet; configuration grows with actual requirements.

Prove locally that the same SDK can be built and initialized through:

- **iOS:** build the bindings and a minimal Apple integration package; initialize through that package in the existing app.
- **Web:** create a minimal new web target and browser integration package that loads the WASM SDK and demonstrates initialization. This is the starting scaffold for the web app; it has no chat or other product functionality yet.
- **CLI:** create a Rust command-line application consuming the SDK directly, using a parser such as `clap`. Initially it only initializes the SDK and reports success or failure. It is the concrete headless host and can be exercised by automated tests without either UI application.

Include repeatable `just` commands, native/WASM checks, and setup documentation. Scope packaging and CI in the issue. Host packages start as thin initialization wrappers: this proves build integration and a basic async call. Streaming, cancellation, and reactivity come later.

### 2. Parsing and context algorithms

Extract independent algorithms and replace their actual Swift call paths. Split into one or several issues based on the boundaries found during scoping; persistence stays in Swift.

### 3. Provider clients and HTTP

Move provider implementations one at a time, with a separate issue for each provider type. Candidates include OpenAI-compatible, Anthropic, and relay paths; confirm the full inventory and order when scoping them.

Develop async networking, streaming, and shared infrastructure from these working integrations.

### Choosing later increments

Leave subsequent order open. Use the updated system map and completed work to choose a bounded responsibility with:

- Few dependencies on unextracted code and a small iOS adapter.
- Understood failure consequences and a recovery path.
- A useful SDK property to exercise next.

Move upward into orchestration when practical; avoid accumulating disconnected utilities.

### Properties to exercise progressively

We need working evidence for the following properties across the migration. An individual extraction should address only those relevant to its responsibility.

| Property | What we need to learn |
| --- | --- |
| Value-based interfaces | Domain inputs, outputs, errors, and ownership translate cleanly between Rust and host languages |
| Asynchronous execution | Cancellation, task lifetime, failures, and concurrent operations behave correctly across bindings |
| Streaming | Events arrive in order, incremental results remain usable, and slow consumers or cancelled subscriptions are handled |
| UI reactivity | SDK state and changes drive native UI updates with clear ownership, subscription lifetime, and thread/actor boundaries |
| Networking | Requests and streamed responses work on native and browser runtimes, including their different transport constraints |
| Platform adapters | The host can supply native services through explicit interfaces, including async results, errors, and missing capabilities |
| Durable state | Ownership, schema evolution, observation, and migration preserve user data and allow a defined recovery path |
| Composition | Higher-level Rust services reuse extracted components and allow lower-level app bindings to be retired |

Record the properties actually exercised in the implementation log. Host-dependent capabilities need explicit adapters and availability behavior.

## Verification

Every increment must remain usable headless and compile for WASM. Browser-sensitive operations also need runtime tests; compilation alone cannot prove networking or storage behavior.

- Test behavior through Rust APIs and exercise the CLI as the headless integration surface.
- Test host packages and bindings separately from views; fake unavailable services at their boundaries.
- Verify affected iOS flows, including relevant errors and cancellation.
- Document deliberate behavior changes and delete replaced implementations when the increment is complete.

## Decisions still open

Resolve these in implementation issues as needed:

- Initial packaging, build/CI setup, initialization API, and host verification.
- Algorithm selection, provider inventory, and issue boundaries.
- Async/event interfaces, UI observation, batching, and cancellation.
- Deprecation tooling and public compatibility/versioning policy.
- Persistence engine, schema, migration, and PAL ownership.
- Crate boundaries and the stable public SDK surface.

## Decision log

Keep the main sections current; retain superseded decisions here. Link future entries to their issue or MR.

| ID | Status | Decision | Rationale / source |
| --- | --- | --- | --- |
| D1 | Working agreement | Extract bounded components incrementally and keep iOS shippable after each increment | Latest incremental revision of #145 and migration discussion; limits integration risk |
| D2 | Working agreement | Allow provisional Swift bindings and move the app-facing boundary upward over time | Enables bottom-up implementation without designing the entire SDK surface first |
| D3 | Working agreement | Treat headless use and WASM compatibility as constraints from the start | #145; exposes hidden platform dependencies during extraction |
| D4 | Superseded by D7 | Start directly with a small, independent lower-level component | Revised to establish SDK initialization across hosts before extracting behavior |
| D5 | Migration goal | Coordinate the durable-data transition with decisions about PAL | Reduce repeated user migrations while preserving the distinction between PAL and chat storage |
| D6 | Deferred | Choose crate boundaries, storage engine, and final public interfaces as working increments provide evidence | Avoid committing to structures before their requirements are known |
| D7 | Working agreement | Start with async SDK initialization in iOS, a minimal new WASM web target, and a Rust CLI, with commands and documentation | Prove local build and integration before moving behavior; the CLI is the concrete headless consumer |
| D8 | Working agreement | Follow with parsing/context algorithms, then provider clients one provider type per issue; leave later order open | Grow the agent harness from bounded components while Swift retains orchestration |
| D9 | Working agreement | Put independently testable host integration packages between bindings and UI applications, starting with initialization | Centralize runtime adaptation and reusable platform services while keeping agent orchestration in Rust and presentation in the app |

## Implementation log

No SDK increments have been completed under this plan yet.

For each completed increment, add:

- **Issue / MR:** links to scope and implementation.
- **Responsibility moved:** what Rust now owns.
- **Integration:** what iOS calls and which adapters remain.
- **Verification:** native, headless, WASM/browser, and affected app checks actually performed; which SDK properties they exercised.
- **Removed code:** replaced Swift implementations and retired bindings.
- **Lessons / next decisions:** evidence that should influence the next increment.

Keep this log factual. Track unfinished work in linked issues rather than recording it as completed here.
