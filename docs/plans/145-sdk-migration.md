# SDK migration insights

Lessons and working conventions for building the SDK. Add new evidence to the relevant insight; link its source issue. Keep implementation scope, test-run results, and merge status in issues and MRs.

Direction: move agent behavior into the SDK while keeping iOS shippable. The agent loop and durable app data remain host-owned until their own extractions. Sources: [#145], [SDK milestone].

## Structure and ownership

- **Extract a usable responsibility.** Inspect callers, preserve supported behavior, wire the real app path, and remove the replaced implementation. A collection of disconnected utilities does not establish an SDK integration. Source: [#145].
- **Keep domain behavior together.** Provider-specific behavior belongs under its provider module; shared messages and events belong at the inference root. Promote shared code when two implementations need it, rather than designing a provider framework upfront. Sources: [#332], [#335].
- **Separate bindings from runtime adaptation.** Generated bindings expose SDK types and operations. Independently testable Apple and browser packages adapt them to their runtimes. UI applications supply composition, lifecycle, permissions, and presentation. Sources: [#330], [#332].
- **Pass values and explicit capabilities.** SDK operations should not depend on SwiftData objects, app containers, or implicit credentials. Move transient computation before deciding durable-storage ownership. Sources: [#145], [#332].
- **Model the capability the operation needs.** A wallet collection can supply a spendable credential and record rejection. This keeps storage schemas, purchases, and balance refresh outside the inference contract; a generic secrets API is unnecessary for that boundary. Source: [#335].
- **Keep provisional APIs visibly experimental.** Low-level bindings may be retired as the app-facing boundary moves upward. Apple uses `Experimental`, CLI inference sits under `experimental`, and the browser package is experimental as a whole. External compatibility promises require a separate policy. Sources: [#145], [#335].

## Naming and API shape

- **Name concrete implementations explicitly.** `OpenAiCompatibleStream` and `EiginRelayStream` identify provider-specific handles. Reserve generic names for shared concepts and host-facing wrappers. Source: [#335].
- **Use `*SDKConversion` for value mapping.** Keep app-to-SDK conversion separate from legacy persisted-data decoding. Capability adapters that select credentials or update host state have behavior beyond conversion. Sources: [#332], [#335].
- **Keep sibling provider lifecycles consistent.** Streams expose `open`, awaited `next`, and `cancel`. Opening validates the initial response; each next call waits for one event. A host wrapper can present both providers through the same consumption interface. Sources: [#332], [#335].
- **Reject missing required configuration at construction.** Passing an error into an operation just to preserve a nonthrowing factory obscures validation. A fallible provider constructor makes the failure boundary explicit. Source: [#335].
- **Separate cancellation mechanics from error translation.** Task or signal cancellation is reusable across operations. Inference-specific error mapping belongs beside inference. Source: [#335].

## Async work and host boundaries

- **Forward cancellation explicitly across bindings.** Cancelling a foreign task does not automatically cancel SDK work. Host wrappers must connect cancellation to the operation handle, including work waiting for headers or body data. Source: [#332].
- **Guard one pending call per stream.** An operation lease prevents overlapping `open` or `next` calls while allowing independent streams. Dropping an unfinished call cancels its work; a completed call returns its state for the next consumer call. Sources: [#332], [#335].
- **Use an explicit browser iterator when immediate interruption matters.** An async generator queues `return()` behind a pending read. A custom iterator can cancel that read immediately. Source: [#332].
- **Use binding-compatible host callbacks.** UniFFI 0.31.0 async callback traits failed Swift 6 checks. Synchronous callbacks with single-use completion handles support async host HTTP without patching generated code. A callback named `open` generated invalid C; `start_request` avoids that generator problem. Source: [#332].
- **Preserve host networking.** Apple supplies URLSession; browsers supply Fetch. Native SDK HTTP owns its Tokio runtime so headless consumers need no ambient executor. Share the injected transport across provider attempts to retain host configuration and resource ownership. Sources: [#332], [#335].
- **Keep retry policy above transport.** Relay wallet failover is allowed only after an initial HTTP 402. Network failures, cancellation, and errors after streaming starts must not trigger replay. Source: [#335].
- **Bound failover independently of persistence.** Track attempted credentials within each request. Whole-collection host stores can restore stale snapshots during concurrent writes; persisted rejection alone cannot prevent another attempt with the same credential. Source: [#335].

## Testing and evidence

- **Test at three boundaries.** SDK behavior tests exercise injected capabilities; binding contracts exercise language/runtime translation; host smoke tests exercise the assembled package. Keep UI tests focused on app integration. Sources: [#356], [#332].
- **Keep fixtures out of production exports.** Test-only binding exports provide controlled pending work, typed failures, and callback delivery. Production wrappers need their own smoke tests. Source: [#356].
- **Preserve decoder and error precedence semantics.** A permissive JSON value parser can accept malformed events that a typed host decoder skipped. Carry terminal state such as refusal through later failures, and retain partial HTTP error bodies when reads fail. Source: [#334].
- **Check observable behavior against the code.** Comments can misdescribe fallback values. Capture the actual request or event at the HTTP boundary before porting it. Source: [#333].
- **Preserve error-read stopping conditions.** A byte cap and a completed-line cutoff return at different times when a server stalls. Test partial bodies, line endings, and read failures; document intentional safety bounds in the MR. Source: [#333].
- **Fake the unavailable boundary.** Provider tests inject HTTP responses. Wallet host tests use the real manager and store with a fake Keychain boundary. Avoid separate tests for trivial forwarding when the integrated behavior is covered. Sources: [#332], [#335].
- **Check suspended work, not just immediate success.** Binding tests should cover wakeups, typed failures, independent operations, and cancellation while work is pending. Sources: [#330], [#356], [#332].
- **Test cancellation at transitions.** Exercise both sides of successful opening and replacement of an active attempt. A test that only cancels pending headers misses these races. Source: [#335].
- **Prove streaming before completion.** A controlled endpoint can hold the remainder of a response until the browser observes the first event. Assert delivered text, tool calls, and failures through the real SDK and host transport; keep protocol edge cases in SDK tests. Source: [#335].
- **Isolate process-global test state.** Tests that emit diagnostics must coordinate with tests that install a global receiver. Otherwise unrelated events can invalidate receiver assertions and poison test locks. Source: [#335].
- **WASM compilation is one check.** Browser-sensitive behavior needs runtime tests in Chromium, Firefox, and WebKit. Controlled endpoints establish host integration; deployed CORS, credentials, and endpoint access need separate evidence. Sources: [#330], [#332], [#335].
- **Exercise a headless consumer.** CLI process tests expose ambient-runtime and credential assumptions and verify process cancellation. Keep low-level test commands experimental rather than building a wallet-management product around them. Sources: [#330], [#335].

## Diagnostics and packaging

- **Filter private values before host delivery.** The SDK owns diagnostic structure, severity, and disclosure policy. Hosts own destinations and retention; private values require explicit opt-in. Source: [#357].
- **Use compatible released binding tools together.** UniFFI 0.31.0 and the released `@ubjs` / browser generator 0.31.0-6 work together through `wasm2`. Keep versions aligned and generated outputs behind host packages. Sources: [#330], [#356].
- **Isolate Apple runtime symbols.** A dynamic SDK XCFramework avoids collisions with Firm's existing static Rust library. Keep Firm packaging separate until its boundary changes. Source: [#330].
- **Treat TLS as a packaging dependency.** Native TLS needs explicit Apple deployment targets and dependency notices. The SDK owns the shared notice inventory copied into host resources. Source: [#332].
- **Use the existing build workflow.** Generate bindings and artifacts through `just generate sdk apple|web`; exercise the SDK through `just test sdk`. Setup and toolchain requirements belong in the [SDK development guide], rather than being copied into each extraction. Sources: [#330], [#356].

## Decisions and evidence still needed

These are open constraints, not established capabilities:

- **Durable state:** storage engine, schemas, recovery, observation, and ownership between PAL and chat data. A coordinated user-data migration remains a goal. Sources: [#145], [#154].
- **Higher-level composition:** agent orchestration, reactive UI state, and retirement of low-level host APIs. Keep crate boundaries and the stable public surface open until working integrations establish them. Source: [#145].
- **Host lifecycle and performance:** foreground/background/resume, budget-expiry/checkpoint behavior, transport measurements, and release signing need explicit evidence. A device smoke check does not cover all of these. Source: [#332].
- **Deployed browser access:** controlled streaming tests do not prove production preflight policy or authenticated remote access. The relay source currently has no CORS layer. Source: [#335].
- **Atomic wallet updates:** the host store still rewrites the wallet collection. Request-local exclusions bound retries; atomic updates across purchases, refresh, and different wallets require a separate storage decision. Source: [#335].

[#145]: https://code.eigin.ai/dev/eigin/-/issues/145
[#154]: https://code.eigin.ai/dev/eigin/-/issues/154
[#330]: https://code.eigin.ai/dev/eigin/-/issues/330
[#332]: https://code.eigin.ai/dev/eigin/-/issues/332
[#333]: https://code.eigin.ai/dev/eigin/-/issues/333
[#334]: https://code.eigin.ai/dev/eigin/-/issues/334
[#335]: https://code.eigin.ai/dev/eigin/-/issues/335
[#356]: https://code.eigin.ai/dev/eigin/-/issues/356
[#357]: https://code.eigin.ai/dev/eigin/-/issues/357
[SDK milestone]: https://code.eigin.ai/dev/eigin/-/milestones/2
[SDK development guide]: ../../src/eigin_sdk/README.md
