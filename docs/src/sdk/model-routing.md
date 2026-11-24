# Model routing

The SDK selects cloud models and offline local fallbacks from inventory snapshots and turn requirements supplied by your app. It keeps conversation affinity and uses attempt outcomes to avoid retired, failing, or slow models.

## Create a shared router

Retain one handle across turns and conversations. Each handle owns independent, memory-only health and affinity; recreating it starts empty.

```swift
import EiginSDK

let router = EiginSDK.Experimental.Routing.Router.withCatalog()
```

For Rust, use `eigin_sdk::inference::routing::ModelRouter::with_catalog()`. These constructors use the [SDK model catalog](model-catalog.md). The plain constructor accepts model facts in each inventory for independent policy evaluation.

## Choose models for a turn

1. Supply the provider's available and enabled IDs, current model, conversation identity, and tool/vision/prompt requirements. An empty enabled list offers all available models.
2. Pass the host's computed message reasoning demand. The router combines it with remembered conversation demand.
3. Resolve the model before preparing its prompt. Ask for a replacement with the measured prompt requirements if an attempt fails.

Ranking prefers models that match the turn's reasoning demand. Adjustable models match either preference; catalog rank orders models within each group. Models in the other group remain fallback candidates.

| Operation | Purpose |
| --- | --- |
| `resolve` | Select a turn's model and report the reason for a change. |
| `replacement` | Select an alternative on the same provider, or return none. |
| `can_satisfy` | Check capability and prompt constraints without conceding them; quarantined matches remain a fallback. |
| `reasoning_effort` | Choose an adjustable model's effort using conversation demand. |
| `hedge_candidate` | Select a runner-up using turn-level concessions. |
| `hedge_delay` | Read the delay suggested by recent first-token samples. |

Replacements preserve prepared-prompt fit and exclude unhealthy models. The attempt controller owns when a candidate may start or replace another attempt. The router supplies which model to use.

## Report health and preserve timing

- Replace remote observations at host refresh points. Report completed attempts and silent hedge losses.
- Local health is model-keyed. Remote evidence is provider/model-keyed.
- Supply wall-clock seconds since the Unix epoch. Selection uses request-start time; route-change classification uses decision time after a host refresh.
- Snapshot `replacement_demand` before awaiting that refresh, then pass it to `replacement` so concurrent turns cannot change the pending retry's demand.

## Host responsibilities

The host owns inventory discovery, reachability, local inference, provider settings, and persistence. It also opens [inference streams](inference.md) for the selected models.

## Offline fallback

1. Call `record_reachability` with the host's network observation.
2. Before `resolve`, call `offline_route` with automatic-selection status, the current provider kind, and the first local provider's inventory/readiness.
3. Execute a returned route through the [local capability](inference.md#host-provided-local-models); otherwise continue cloud selection.
4. Report attempt outcomes through the same router so failures and recovery affect the next turn.

Keep the saved cloud provider/model unchanged during a detour. The SDK preserves cloud affinity and activity; pinned selections stay pinned.
