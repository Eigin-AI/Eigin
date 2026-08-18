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

    // MARK: - New models (2026-06 update)

    @Test func gemini35FlashExactMatch() {
        let entry = KnownModelCatalog.lookup("gemini-3.5-flash")
        #expect(entry?.displayName == "Gemini 3.5 Flash")
    }

    @Test func gemini35FlashGoogleModelsPrefix() {
        let entry = KnownModelCatalog.lookup("models/gemini-3.5-flash")
        #expect(entry?.displayName == "Gemini 3.5 Flash")
    }

    @Test func gemini35FlashOpenRouterPrefix() {
        let entry = KnownModelCatalog.lookup("google/gemini-3.5-flash")
        #expect(entry?.displayName == "Gemini 3.5 Flash")
    }

    @Test func gemini31ProPreviewExactMatch() {
        let entry = KnownModelCatalog.lookup("gemini-3.1-pro-preview")
        #expect(entry?.displayName == "Gemini 3.1 Pro Preview")
    }

    @Test func gpt55ExactMatch() {
        let entry = KnownModelCatalog.lookup("gpt-5.5")
        #expect(entry?.displayName == "GPT-5.5")
    }

    @Test func gpt55ProExactMatch() {
        let entry = KnownModelCatalog.lookup("gpt-5.5-pro")
        #expect(entry?.displayName == "GPT-5.5 Pro")
    }

    @Test func claudeOpus48ExactMatch() {
        let entry = KnownModelCatalog.lookup("claude-opus-4-8")
        #expect(entry?.displayName == "Claude Opus 4.8")
    }

    @Test func minimaxM3ExactMatch() {
        let entry = KnownModelCatalog.lookup("minimax-m3")
        #expect(entry?.displayName == "MiniMax M3")
    }

    @Test func kimiK26ExactMatch() {
        // Must match the K2.6 entry, NOT K2 with version tag "6"
        let entry = KnownModelCatalog.lookup("kimi-k2.6")
        #expect(entry?.displayName == "Kimi K2.6")
    }

    @Test func kimiK26NoVersionTag() {
        // "kimi-k2.6" is a distinct model, not K2 with a suffix
        let tag = KnownModelCatalog.versionTag(for: "kimi-k2.6")
        #expect(tag == nil)
    }

    @Test func mistralLargeLatestExactMatch() {
        let entry = KnownModelCatalog.lookup("mistral-large-latest")
        #expect(entry?.displayName == "Mistral Large (latest)")
    }

    @Test func mistralMediumLatestExactMatch() {
        let entry = KnownModelCatalog.lookup("mistral-medium-latest")
        #expect(entry?.displayName == "Mistral Medium (latest)")
    }

    @Test func mistralSmallLatestExactMatch() {
        let entry = KnownModelCatalog.lookup("mistral-small-latest")
        #expect(entry?.displayName == "Mistral Small (latest)")
    }

    @Test func mistralMedium2604ExactMatch() {
        let entry = KnownModelCatalog.lookup("mistral-medium-2604")
        #expect(entry?.displayName == "Mistral Medium 3.5")
    }

    @Test func mistralSmall2603ExactMatch() {
        let entry = KnownModelCatalog.lookup("mistral-small-2603")
        #expect(entry?.displayName == "Mistral Small 4")
    }

    @Test func grok43ExactMatch() {
        let entry = KnownModelCatalog.lookup("grok-4.3")
        #expect(entry?.displayName == "Grok 4.3")
    }

    @Test func deepseekV4ProExactMatch() {
        let entry = KnownModelCatalog.lookup("deepseek-v4-pro")
        #expect(entry?.displayName == "DeepSeek V4 Pro")
    }

    @Test func deepseekV4FlashExactMatch() {
        let entry = KnownModelCatalog.lookup("deepseek-v4-flash")
        #expect(entry?.displayName == "DeepSeek V4 Flash")
    }

    @Test func glm51ExactMatch() {
        let entry = KnownModelCatalog.lookup("glm-5.1")
        #expect(entry?.displayName == "GLM 5.1")
    }

    @Test func qwen37MaxExactMatch() {
        let entry = KnownModelCatalog.lookup("qwen3.7-max")
        #expect(entry?.displayName == "Qwen 3.7 Max")
    }

    @Test func qwen37PlusExactMatch() {
        let entry = KnownModelCatalog.lookup("qwen3.7-plus")
        #expect(entry?.displayName == "Qwen 3.7 Plus")
    }

    // MARK: - New models (2026-07 update)

    @Test func claudeSonnet5ExactMatch() {
        let entry = KnownModelCatalog.lookup("claude-sonnet-5")
        #expect(entry?.displayName == "Claude Sonnet 5")
    }

    @Test func claudeFable5ExactMatch() {
        let entry = KnownModelCatalog.lookup("claude-fable-5")
        #expect(entry?.displayName == "Claude Fable 5")
    }

    @Test func gpt56ExactMatch() {
        let entry = KnownModelCatalog.lookup("gpt-5.6")
        #expect(entry?.displayName == "GPT-5.6")
    }

    @Test func gpt56VariantsDoNotMatchBase() {
        let terra = KnownModelCatalog.lookup("gpt-5.6-terra")
        #expect(terra?.displayName == "GPT-5.6 Terra")

        let luna = KnownModelCatalog.lookup("gpt-5.6-luna")
        #expect(luna?.displayName == "GPT-5.6 Luna")

        let sol = KnownModelCatalog.lookup("gpt-5.6-sol")
        #expect(sol?.displayName == "GPT-5.6 Sol")

        let base = KnownModelCatalog.lookup("gpt-5.6")
        #expect(base?.displayName == "GPT-5.6")
    }

    @Test func glm52ExactMatchNotSwallowedByGlm5() {
        // "glm-5.2" must resolve to the 5.2 entry, not the base "glm-5" entry.
        let entry = KnownModelCatalog.lookup("glm-5.2")
        #expect(entry?.displayName == "GLM 5.2")

        let base = KnownModelCatalog.lookup("glm-5")
        #expect(base?.displayName == "GLM-5")
    }

    @Test func glm5TurboExactMatch() {
        let entry = KnownModelCatalog.lookup("glm-5-turbo")
        #expect(entry?.displayName == "GLM-5 Turbo")
    }

    @Test func glm5vTurboExactMatch() {
        let entry = KnownModelCatalog.lookup("glm-5v-turbo")
        #expect(entry?.displayName == "GLM-5V Turbo")
    }

    @Test func kimiK27CodeExactMatchNotSwallowedByKimiK2() {
        // "kimi-k2.7-code" must resolve to its own entry, not base "kimi-k2".
        let entry = KnownModelCatalog.lookup("kimi-k2.7-code")
        #expect(entry?.displayName == "Kimi K2.7 Code")

        let tag = KnownModelCatalog.versionTag(for: "kimi-k2.7-code")
        #expect(tag == nil)
    }

    @Test func gemma431bExactMatch() {
        let entry = KnownModelCatalog.lookup("gemma-4-31b-it")
        #expect(entry?.displayName == "Gemma 4 31B")
    }

    @Test func gemma431bVendorPrefix() {
        // Relay canonical id: google/gemma-4-31b-it
        let entry = KnownModelCatalog.lookup("google/gemma-4-31b-it")
        #expect(entry?.displayName == "Gemma 4 31B")
    }

    @Test func nvidiaNemotron3SuperExactMatch() {
        let entry = KnownModelCatalog.lookup("nvidia-nemotron-3-super-120b-a12b")
        #expect(entry?.displayName == "Nemotron 3 Super 120B A12B")
        #expect(entry?.family == .nvidia)
    }

    @Test func nvidiaNemotron3SuperVendorPrefix() {
        // Relay canonical id: nvidia/nvidia-nemotron-3-super-120b-a12b
        let entry = KnownModelCatalog.lookup("nvidia/nvidia-nemotron-3-super-120b-a12b")
        #expect(entry?.displayName == "Nemotron 3 Super 120B A12B")
    }

    // MARK: - bestModel(from:)

    @Test func bestModelPicksHighestRanked() {
        let available = ["gpt-4.1", "claude-sonnet-4-6", "mistral-large-2512"]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "claude-sonnet-4-6")
    }

    @Test func bestModelHandlesVendorPrefix() {
        let available = ["openai/gpt-5.4", "anthropic/claude-haiku-4-5"]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "openai/gpt-5.4")
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

    // MARK: - Aliases (fixture-based, decoupled from the live catalog)

    /// Builds a minimal entry for alias tests. Metadata beyond `pattern`/`aliases`
    /// is irrelevant here, so only the display name distinguishes fixtures.
    private func fixture(
        pattern: String,
        aliases: [String] = [],
        displayName: String
    ) -> KnownModelEntry {
        KnownModelEntry(
            pattern: pattern,
            aliases: aliases,
            displayName: displayName,
            family: .mistral,
            contextWindow: 1000,
            maxOutput: nil,
            inputCostPerMillion: nil,
            outputCostPerMillion: nil,
            supportsToolCall: false,
            supportsReasoning: false,
            supportsVision: false,
            isRecommended: false
        )
    }

    @Test func aliasResolvesToEntry() {
        let entries = [
            fixture(
                pattern: "canonical-model",
                aliases: ["vendor-variant"],
                displayName: "Canonical"
            ),
        ]
        let match = KnownModelCatalog.lookup("vendor-variant", in: entries)
        #expect(match?.entry.displayName == "Canonical")
        #expect(match?.matched == "vendor-variant")
    }

    @Test func aliasResolvesWithVersionSuffix() {
        // matchesPattern reuse: a trailing date/version after the alias still matches.
        let entries = [
            fixture(
                pattern: "canonical-model",
                aliases: ["vendor-variant"],
                displayName: "Canonical"
            ),
        ]
        let match = KnownModelCatalog.lookup("vendor-variant-20260101", in: entries)
        #expect(match?.entry.displayName == "Canonical")
    }

    @Test func aliasResolvesWithVendorPrefix() {
        let entries = [
            fixture(
                pattern: "canonical-model",
                aliases: ["vendor-variant"],
                displayName: "Canonical"
            ),
        ]
        let match = KnownModelCatalog.lookup("berget/vendor-variant", in: entries)
        #expect(match?.entry.displayName == "Canonical")
    }

    @Test func versionTagUsesMatchedAliasNotPattern() {
        // Chopping must use the alias length, not the (longer/shorter) pattern length.
        let entries = [
            fixture(pattern: "canonical-model", aliases: ["var"], displayName: "Canonical"),
        ]
        let tag = KnownModelCatalog.versionTag(for: "var-20260101", in: entries)
        #expect(tag == "20260101")
    }

    @Test func firstMatchOrderingHoldsAcrossAliases() {
        // An earlier entry's alias wins over a later entry, mirroring pattern ordering.
        let entries = [
            fixture(pattern: "first", aliases: ["shared"], displayName: "First"),
            fixture(pattern: "shared", displayName: "Second"),
        ]
        let match = KnownModelCatalog.lookup("shared", in: entries)
        #expect(match?.entry.displayName == "First")
    }

    @Test func bergetMistralAliasResolvesInLiveCatalog() {
        // One smoke test that the real wiring folds Berget's spelling into the canonical entry.
        let entry = KnownModelCatalog.lookup("Mistral-Medium-3.5-128B")
        #expect(entry?.displayName == "Mistral Medium 3.5")
        #expect(entry?.outputCostPerMillion == 7.50)
    }

    @Test func mistralVersionAliasesResolveInLiveCatalog() {
        #expect(KnownModelCatalog.lookup("mistral-large-3")?.displayName == "Mistral Large 3")
        #expect(KnownModelCatalog.lookup("mistral-small-3.1")?.displayName == "Mistral Small 3.1")
    }

    @Test func mistralSmall4AliasResolvesInLiveCatalog() {
        // Providers serve Mistral Small 4 by name rather than the 2603 date stamp.
        #expect(KnownModelCatalog.lookup("mistral-small-4")?.displayName == "Mistral Small 4")
        #expect(KnownModelCatalog.lookup("mistral-small-4-119b")?.displayName == "Mistral Small 4")
    }

    @Test func nemotronAliasWithoutVendorPrefixResolves() {
        // Many providers list Nemotron without the leading `nvidia-`.
        let entry = KnownModelCatalog.lookup("nemotron-3-super-120b-a12b")
        #expect(entry?.displayName == "Nemotron 3 Super 120B A12B")
    }

    @Test func mistralMedium3AliasDoesNotSwallow35() {
        // "mistral-medium-3" and "mistral-medium-3-5" are aliases on different entries.
        // Ordering must keep them distinct.
        #expect(KnownModelCatalog.lookup("mistral-medium-3")?.displayName == "Mistral Medium 3")
        #expect(KnownModelCatalog.lookup("mistral-medium-3-5")?.displayName == "Mistral Medium 3.5")
    }
}
