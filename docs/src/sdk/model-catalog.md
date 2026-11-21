# Model catalog

Use the SDK catalog to look up model capabilities and choose a default from a provider's model IDs. The catalog is bundled with the SDK and works offline. Your app supplies the available models and the user's enabled-model choices.

## Look up and choose models

```swift
import EiginSDK

let offers = ["openai/gpt-4.1", "provider/custom-model"]
let preferred = EiginSDK.ModelCatalog.bestModel(from: offers)
let metadata = EiginSDK.ModelCatalog.lookup(offers[0])?.entry
```

For Rust, start with `eigin_sdk::model_catalog::ModelCatalog::default_catalog()`.

For browsers:

```typescript
import { initialize, ModelCatalog } from "@eigin/sdk";

await initialize();
const catalog = ModelCatalog.defaultCatalog();
const preferred = catalog.bestModel(["openai/gpt-4.1", "provider/custom-model"]);
```

| Method | Use it to |
| --- | --- |
| `lookup` | Read capabilities, limits, prices, and a version tag. Unknown IDs return no result. |
| `knownModels` | Filter to recognized models, keeping the offered IDs and their order. |
| `bestModel` | Choose the highest-preference offer, then fall back to the first known model or first offer. Empty input returns no result. |
| `preferenceRank` | Sort by the resolved model's position in the preference list. Unknown or unranked models have no rank. |

Lookup recognizes provider prefixes, aliases, and version suffixes. Selection matches preference patterns against offered IDs directly; ranking resolves aliases first. An alias can therefore have a rank while selection reaches it through the fallback. Your app decides how to sort equal ranks.

## Reasoning and image allowances

- `reasoningControl` returns supported efforts and fast/escalated choices for a verified model and endpoint. Your app decides whether the turn needs reasoning.
- `boundedReasoningEffort` applies that control's default and cap before sending a request. Without a verified control, it returns the requested effort unchanged.
- `imageInputBudget` estimates an image's context cost. Add it to the context message's `additionalInputTokens`. Missing dimensions use 1024×1024; unknown models receive a conservative allowance.

Browser dimensions, token counts, and ranks use `bigint`. Public APIs currently use the bundled catalog.
