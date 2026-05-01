@testable import Eigin
import Foundation
import Testing

@Suite("KnownModelCatalog")
struct KnownModelCatalogTests {
    // MARK: - GPT-4.1 variants

    @Test func gpt41ExactMatch() {
        let entry = KnownModelCatalog.lookup("gpt-4.1")
        #expect(entry?.displayName == "GPT-4.1")
    }

    @Test func gpt41DateSuffix() {
        // OpenAI date-stamped snapshot
        let entry = KnownModelCatalog.lookup("gpt-4.1-2025-04-14")
        #expect(entry?.displayName == "GPT-4.1")
    }

    @Test func gpt41OpenRouterPrefix() {
        // OpenRouter vendor prefix: openai/gpt-4.1
        let entry = KnownModelCatalog.lookup("openai/gpt-4.1")
        #expect(entry?.displayName == "GPT-4.1")
    }

    @Test func gpt41MiniDoesNotMatchParent() {
        let mini = KnownModelCatalog.lookup("gpt-4.1-mini")
        #expect(mini?.displayName == "GPT-4.1 Mini")

        let base = KnownModelCatalog.lookup("gpt-4.1")
        #expect(base?.displayName == "GPT-4.1")
    }

    // MARK: - Claude Sonnet 4.6 variants

    @Test func claudeSonnet46ExactMatch() {
        let entry = KnownModelCatalog.lookup("claude-sonnet-4-6")
        #expect(entry?.displayName == "Claude Sonnet 4.6")
    }

    @Test func claudeSonnet46DateSuffix() {
        // Anthropic API date-stamped ID
        let entry = KnownModelCatalog.lookup("claude-sonnet-4-6-20260217")
        #expect(entry?.displayName == "Claude Sonnet 4.6")
    }

    @Test func claudeSonnet46VendorPrefix() {
        // Provider using anthropic/ prefix with dashes
        let entry = KnownModelCatalog.lookup("anthropic/claude-sonnet-4-6")
        #expect(entry?.displayName == "Claude Sonnet 4.6")
    }

    @Test func claudeSonnet46OpenRouterDotFormat() {
        // OpenRouter uses dots: anthropic/claude-sonnet-4.6
        let entry = KnownModelCatalog.lookup("anthropic/claude-sonnet-4.6")
        #expect(entry?.displayName == "Claude Sonnet 4.6")
    }

    @Test func claudeSonnet46VertexAIAtSeparator() {
        // GCP Vertex AI format: claude-sonnet-4-6@20260217
        let entry = KnownModelCatalog.lookup("claude-sonnet-4-6@20260217")
        #expect(entry?.displayName == "Claude Sonnet 4.6")
    }

    // MARK: - Gemini 2.5 Flash variants

    @Test func gemini25FlashExactMatch() {
        let entry = KnownModelCatalog.lookup("gemini-2.5-flash")
        #expect(entry?.displayName == "Gemini 2.5 Flash")
    }

    @Test func gemini25FlashGoogleModelsPrefix() {
        // Google API resource path: models/gemini-2.5-flash
        let entry = KnownModelCatalog.lookup("models/gemini-2.5-flash")
        #expect(entry?.displayName == "Gemini 2.5 Flash")
    }

    @Test func gemini25FlashOpenRouterPrefix() {
        // OpenRouter vendor prefix: google/gemini-2.5-flash
        let entry = KnownModelCatalog.lookup("google/gemini-2.5-flash")
        #expect(entry?.displayName == "Gemini 2.5 Flash")
    }

    // MARK: - Claude Haiku naming evolution

    @Test func claudeHaiku45NewNamingScheme() {
        // Post-4.x naming: claude-haiku-4-5
        let entry = KnownModelCatalog.lookup("claude-haiku-4-5")
        #expect(entry?.displayName == "Claude Haiku 4.5")
    }

    @Test func claudeHaiku45DateSuffix() {
        let entry = KnownModelCatalog.lookup("claude-haiku-4-5-20251001")
        #expect(entry?.displayName == "Claude Haiku 4.5")
    }

    @Test func claudeHaiku45OpenRouterDotFormat() {
        // OpenRouter: anthropic/claude-haiku-4.5
        let entry = KnownModelCatalog.lookup("anthropic/claude-haiku-4.5")
        #expect(entry?.displayName == "Claude Haiku 4.5")
    }

    @Test func claudeHaiku45VertexAIAtSeparator() {
        // GCP Vertex AI: claude-haiku-4-5@20251001
        let entry = KnownModelCatalog.lookup("claude-haiku-4-5@20251001")
        #expect(entry?.displayName == "Claude Haiku 4.5")
    }

    // MARK: - Version tag extraction

    @Test func versionTagFromDateSuffix() {
        // claude-haiku-4-5-20251001 → "20251001"
        let tag = KnownModelCatalog.versionTag(for: "claude-haiku-4-5-20251001")
        #expect(tag == "20251001")
    }

    @Test func versionTagFromOpenAIDate() {
        // gpt-4.1-2025-04-14 → "2025-04-14"
        let tag = KnownModelCatalog.versionTag(for: "gpt-4.1-2025-04-14")
        #expect(tag == "2025-04-14")
    }

    @Test func versionTagFromVertexAIFormat() {
        // claude-sonnet-4-6@20260217 → "20260217"
        let tag = KnownModelCatalog.versionTag(for: "claude-sonnet-4-6@20260217")
        #expect(tag == "20260217")
    }

    @Test func versionTagNilForExactMatch() {
        // No suffix → nil
        let tag = KnownModelCatalog.versionTag(for: "claude-sonnet-4-6")
        #expect(tag == nil)
    }

    @Test func versionTagNilForUnknownModel() {
        let tag = KnownModelCatalog.versionTag(for: "totally-unknown")
        #expect(tag == nil)
    }

    @Test func versionTagStrippedFromVendorPrefix() {
        // anthropic/claude-haiku-4-5-20251001 → "20251001"
        let tag = KnownModelCatalog.versionTag(for: "anthropic/claude-haiku-4-5-20251001")
        #expect(tag == "20251001")
    }

    // MARK: - Kimi K2 / K2.5

    @Test func kimiK2ExactMatch() {
        let entry = KnownModelCatalog.lookup("kimi-k2")
        #expect(entry?.displayName == "Kimi K2")
    }

    @Test func kimiK25ExactMatch() {
        // Must match the K2.5 entry, NOT K2 with version tag "5"
        let entry = KnownModelCatalog.lookup("kimi-k2.5")
        #expect(entry?.displayName == "Kimi K2.5")
    }

    @Test func kimiK25NoVersionTag() {
        // "kimi-k2.5" is a distinct model, not K2 with a suffix
        let tag = KnownModelCatalog.versionTag(for: "kimi-k2.5")
        #expect(tag == nil)
    }

    // MARK: - General

    @Test func unknownModelReturnsNil() {
        let entry = KnownModelCatalog.lookup("totally-unknown-model")
        #expect(entry == nil)
    }

    @Test func catalogServiceOmitsUnknownModels() async {
        let service = CatalogModelMetadataService()
        let results = await service.enrich(
            modelIDs: ["gpt-4.1", "unknown-model", "claude-sonnet-4-6"],
            provider: "test"
        )
        #expect(results.count == 2)
        #expect(results[0].id == "gpt-4.1")
        #expect(results[1].id == "claude-sonnet-4-6")
    }

    // MARK: - Apple Foundation Model

    @Test func appleFoundationModelExactMatch() {
        let entry = KnownModelCatalog.lookup("apple-foundation-model")
        #expect(entry?.displayName == "Apple Foundation Model")
        #expect(entry?.family == .apple)
        #expect(entry?.contextWindow == 4096)
        #expect(entry?.supportsToolCall == true)
        #expect(entry?.inputCostPerMillion == nil)
    }

    // MARK: - ProviderPreset.isLocal

    @Test func isLocalForApplePreset() {
        #expect(ProviderPreset.isLocal("local://apple-foundation-model") == true)
    }

    @Test func isLocalForFutureLocalProvider() {
        #expect(ProviderPreset.isLocal("local://ollama") == true)
    }

    @Test func isLocalFalseForHTTPS() {
        #expect(ProviderPreset.isLocal("https://api.openai.com/v1") == false)
    }

    // MARK: - General

    // MARK: - Case-insensitive matching

    @Test func glm47MixedCaseWithQuantSuffix() {
        let entry = KnownModelCatalog.lookup("zai-org/GLM-4.7-FP8")
        #expect(entry?.displayName == "GLM 4.7")
    }

    @Test func deepseekV31TerminusMixedCase() {
        let entry = KnownModelCatalog.lookup("DeepSeek-V3.1-Terminus")
        #expect(entry?.displayName == "DeepSeek V3.1 Terminus")
    }

    @Test func deepseekV32MixedCase() {
        let entry = KnownModelCatalog.lookup("DeepSeek-V3.2")
        #expect(entry?.displayName == "DeepSeek V3.2")
    }

    @Test func minimaxM25MixedCase() {
        let entry = KnownModelCatalog.lookup("MiniMax-M2.5")
        #expect(entry?.displayName == "MiniMax M2.5")
    }

    // MARK: - bestModel(from:)

    @Test func bestModelPicksHighestRanked() {
        let available = ["gpt-4.1", "claude-sonnet-4-6", "mistral-large-2512"]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "claude-sonnet-4-6")
    }

    @Test func bestModelHandlesVendorPrefix() {
        let available = ["openai/gpt-5.2", "anthropic/claude-haiku-4-5"]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "openai/gpt-5.2")
    }

    @Test func bestModelHandlesDotFormat() {
        let available = ["anthropic/claude-sonnet-4.6", "google/gemini-2.5-flash"]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "anthropic/claude-sonnet-4.6")
    }

    @Test func bestModelFallsToCatalogKnownWhenNoRankingMatch() {
        // A model that's in the catalog but not in preferenceRanking shouldn't exist,
        // but test the fallback: if none match ranking, pick first catalog-known.
        let available = ["some-unknown-model", "gpt-4.1"]
        let best = KnownModelCatalog.bestModel(from: available)
        // gpt-4.1 is in the ranking, so it should match
        #expect(best == "gpt-4.1")
    }

    @Test func bestModelFallsToFirstAvailableWhenNothingKnown() {
        let available = ["totally-unknown-a", "totally-unknown-b"]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "totally-unknown-a")
    }

    @Test func bestModelReturnsNilForEmptyList() {
        let best = KnownModelCatalog.bestModel(from: [])
        #expect(best == nil)
    }

    @Test func bestModelWithDateSuffix() {
        let available = ["claude-sonnet-4-6-20260217", "gpt-4.1-mini"]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "claude-sonnet-4-6-20260217")
    }

    @Test func allEntriesHavePositiveContextWindow() {
        for entry in KnownModelCatalog.entries {
            #expect(
                entry.contextWindow > 0, "Entry \(entry.pattern) has non-positive context window"
            )
        }
    }
}
