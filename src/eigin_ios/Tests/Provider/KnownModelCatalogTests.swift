@testable import Eigin
import Foundation
import Testing

/// Behavior tests for ``KnownModelCatalog``.
///
/// Model-specific behavior is covered by rules and invariants over the whole
/// catalog (every pattern/alias resolving, ranking entries resolving, ordering
/// guarantees) plus fixture-based tests for the matching and selection rules
/// themselves. New catalog entries are automatically covered by the invariants.
@Suite("KnownModelCatalog")
struct KnownModelCatalogTests {
    // MARK: - Matching rules

    @Test func exactMatch() {
        let entry = fixture(pattern: "gpt-4.1", displayName: "GPT-4.1")
        #expect(KnownModelCatalog.lookup("gpt-4.1", in: [entry])?.entry.displayName == "GPT-4.1")
    }

    @Test func matchingIsCaseAndDotInsensitive() {
        // IDs are lowercased and `.` ↔ `-` normalized before matching.
        let entry = fixture(pattern: "glm-4.7", displayName: "GLM 4.7")
        #expect(KnownModelCatalog.lookup("GLM-4.7", in: [entry]) != nil)
        #expect(KnownModelCatalog.lookup("GLM-4-7", in: [entry]) != nil)
        #expect(KnownModelCatalog.lookup("glm-4.7", in: [entry]) != nil)
    }

    @Test func vendorPrefixIsStripped() {
        // Relay canonical / vendor / resource-path prefixes all resolve.
        let entry = fixture(pattern: "glm-5.3", displayName: "GLM 5.3")
        #expect(KnownModelCatalog.lookup("z-ai/glm-5.3", in: [entry]) != nil)
        #expect(KnownModelCatalog.lookup(
            "openai/gpt-4.1",
            in: [fixture(pattern: "gpt-4.1", displayName: "GPT-4.1")]
        ) != nil)
        #expect(KnownModelCatalog.lookup(
            "models/gemini-2.5-flash",
            in: [fixture(pattern: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash")]
        ) != nil)
    }

    @Test func versionSuffixStillMatches() {
        // Date-stamped / versioned snapshots match the base entry…
        let entry = fixture(pattern: "gpt-4.1", displayName: "GPT-4.1")
        #expect(KnownModelCatalog.lookup("gpt-4.1-2025-04-14", in: [entry]) != nil)
        #expect(KnownModelCatalog.lookup(
            "claude-sonnet-4-6-20260217",
            in: [fixture(pattern: "claude-sonnet-4-6", displayName: "S")]
        ) != nil)
        #expect(KnownModelCatalog.lookup(
            "claude-sonnet-4-6@20260217",
            in: [fixture(pattern: "claude-sonnet-4-6", displayName: "S")]
        ) != nil)
    }

    @Test func variantNameDoesNotMatchParent() {
        // A lettered variant is a different model, never swallowed by its parent.
        let mini = fixture(pattern: "gpt-4.1-mini", displayName: "Mini")
        let parent = fixture(pattern: "gpt-4.1", displayName: "Parent")
        #expect(KnownModelCatalog.lookup("gpt-4.1-mini", in: [parent]) == nil)
        #expect(KnownModelCatalog.lookup("gpt-4.1-mini", in: [parent, mini])?.entry
            .displayName == "Mini")
    }

    @Test func quantizationSuffixIsIgnored() {
        // Provider quantization tags don't break the match.
        let entry = fixture(pattern: "glm-4.7", displayName: "GLM 4.7")
        #expect(KnownModelCatalog.lookup("zai-org/GLM-4.7-FP8", in: [entry]) != nil)
        #expect(KnownModelCatalog.lookup("glm-4.7-awq", in: [entry]) != nil)
    }

    @Test func unknownModelReturnsNil() {
        #expect(KnownModelCatalog.lookup("totally-unknown-model", in: []) == nil)
        #expect(KnownModelCatalog.lookup("totally-unknown-model") == nil)
    }

    // MARK: - Ordering

    @Test func firstMatchWins() {
        // Lookup walks entries top to bottom; the earlier entry takes precedence.
        let first = fixture(pattern: "shared", displayName: "First")
        let second = fixture(pattern: "shared", displayName: "Second")
        #expect(KnownModelCatalog.lookup("shared", in: [first, second])?.entry
            .displayName == "First")
    }

    @Test func longerPatternMustPrecedeShorterSibling() {
        // A shorter pattern with a digit suffix would swallow its sibling; the
        // entry order is the only protection, so it's part of the contract.
        let sibling = fixture(pattern: "kimi-k2.5", displayName: "K2.5")
        let parent = fixture(pattern: "kimi-k2", displayName: "K2")
        #expect(KnownModelCatalog.lookup("kimi-k2.5", in: [parent, sibling])?.entry
            .displayName == "K2")
        #expect(KnownModelCatalog.lookup("kimi-k2.5", in: [sibling, parent])?.entry
            .displayName == "K2.5")
    }

    @Test func firstMatchHoldsAcrossAliases() {
        // An earlier entry's alias wins over a later entry too.
        let first = fixture(pattern: "first", aliases: ["shared"], displayName: "First")
        let second = fixture(pattern: "shared", displayName: "Second")
        #expect(KnownModelCatalog.lookup("shared", in: [first, second])?.entry
            .displayName == "First")
    }

    // MARK: - Version tags

    @Test func versionTagExtractedFromSuffix() {
        #expect(KnownModelCatalog.versionTag(
            for: "claude-haiku-4-5-20251001",
            in: [fixture(pattern: "claude-haiku-4-5", displayName: "H")]
        ) == "20251001")
        #expect(KnownModelCatalog.versionTag(
            for: "gpt-4.1-2025-04-14",
            in: [fixture(pattern: "gpt-4.1", displayName: "G")]
        ) == "2025-04-14")
        #expect(KnownModelCatalog.versionTag(
            for: "claude-sonnet-4-6@20260217",
            in: [fixture(pattern: "claude-sonnet-4-6", displayName: "S")]
        ) == "20260217")
    }

    @Test func versionTagExtractedFromVendorPrefixedID() {
        let entry = fixture(pattern: "claude-haiku-4-5", displayName: "H")
        #expect(KnownModelCatalog.versionTag(
            for: "anthropic/claude-haiku-4-5-20251001",
            in: [entry]
        ) == "20251001")
    }

    @Test func versionTagNilForExactMatchAndUnknown() {
        #expect(KnownModelCatalog.versionTag(
            for: "claude-sonnet-4-6",
            in: [fixture(pattern: "claude-sonnet-4-6", displayName: "S")]
        ) == nil)
        #expect(KnownModelCatalog.versionTag(for: "totally-unknown", in: []) == nil)
    }

    @Test func versionTagChopsByMatchedAliasNotPattern() {
        // The matched string (alias or pattern) defines the chop point.
        let entry = fixture(pattern: "canonical-model", aliases: ["var"], displayName: "Canonical")
        #expect(KnownModelCatalog.versionTag(for: "var-20260101", in: [entry]) == "20260101")
    }

    @Test func versionTagNilSinceSiblingIsDistinctModel() {
        // "kimi-k2.5" is a distinct model, not K2 with a suffix — the entry all
        // by itself matches exactly, so no tag.
        let entry = fixture(pattern: "kimi-k2", displayName: "K2")
        #expect(KnownModelCatalog.versionTag(for: "kimi-k2", in: [entry]) == nil)
    }

    // MARK: - Aliases

    @Test func aliasResolvesToEntry() {
        let entry = fixture(
            pattern: "canonical-model",
            aliases: ["vendor-variant"],
            displayName: "Canonical"
        )
        let match = KnownModelCatalog.lookup("vendor-variant", in: [entry])
        #expect(match?.entry.displayName == "Canonical")
        #expect(match?.matched == "vendor-variant")
    }

    @Test func aliasMatchesWithPrefixAndSuffix() {
        let entry = fixture(
            pattern: "canonical-model",
            aliases: ["vendor-variant"],
            displayName: "Canonical"
        )
        #expect(KnownModelCatalog.lookup("berget/vendor-variant", in: [entry]) != nil)
        #expect(KnownModelCatalog.lookup("vendor-variant-20260101", in: [entry]) != nil)
    }

    // MARK: - Catalog invariants (live catalog)

    /// Every pattern and alias in the live catalog must resolve back to its own
    /// entry — this is the ordering/first-match protection contract, and it
    /// keeps any future entry from being silently swallowed.
    @Test func everyPatternAndAliasResolvesToItsOwnEntry() {
        for entry in KnownModelCatalog.entries {
            for candidate in [entry.pattern] + entry.aliases {
                let match = KnownModelCatalog.lookup(candidate)
                #expect(
                    match?.displayName == entry.displayName,
                    "'\(candidate)' resolved to \(match?.displayName ?? "nil"), expected '\(entry.displayName)' — order the longer/more specific pattern first"
                )
            }
        }
    }

    @Test func allEntriesHavePositiveContextWindow() {
        for entry in KnownModelCatalog.entries {
            #expect(
                entry.contextWindow > 0,
                "Entry \(entry.pattern) has non-positive context window"
            )
        }
    }

    /// Every preferenceRanking pattern must resolve in the catalog — a typo or
    /// removed entry would otherwise silently never match during auto-select.
    @Test func everyRankingEntryResolvesInCatalog() {
        for pattern in KnownModelCatalog.preferenceRanking {
            #expect(
                KnownModelCatalog.lookup(pattern) != nil,
                "ranking entry '\(pattern)' has no catalog entry"
            )
        }
    }

    /// No two entries may claim the same pattern or alias: first-match would
    /// make the later entry dead weight.
    @Test func patternsAndAliasesAreUniqueAcrossEntries() {
        var seen: [String: String] = [:]
        for entry in KnownModelCatalog.entries {
            for candidate in [entry.pattern] + entry.aliases {
                let key = candidate.lowercased()
                #expect(
                    seen[key] == nil,
                    "'\(candidate)' is claimed by both '\(seen[key] ?? "?")' and '\(entry.displayName)'"
                )
                seen[key] = entry.displayName
            }
        }
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

    // MARK: - Model selection rules (fixture-based)

    @Test func selectionWalksRankingTopDown() {
        let available = ["gpt-4.1", "claude-sonnet-4-6"]
        let best = KnownModelCatalog.bestModel(
            from: available,
            ranking: ["claude-sonnet-4-6", "gpt-4.1"],
            in: KnownModelCatalog.entries
        )
        #expect(best == "claude-sonnet-4-6")
    }

    @Test func selectionHandlesPrefixesDotsAndDateSuffixes() {
        // Vendor-prefixed and dot-format IDs match the ranking entry; the first
        // matching occurrence in `available` wins.
        let best = KnownModelCatalog.bestModel(
            from: ["anthropic/claude-sonnet-4.6", "google/gemini-2.5-flash"],
            ranking: ["claude-sonnet-4-6", "gemini-2.5-flash"],
            in: KnownModelCatalog.entries
        )
        #expect(best == "anthropic/claude-sonnet-4.6")

        #expect(
            KnownModelCatalog.bestModel(
                from: ["claude-sonnet-4-6-20260217"],
                ranking: ["claude-sonnet-4-6"],
                in: KnownModelCatalog.entries
            ) == "claude-sonnet-4-6-20260217"
        )
    }

    @Test func selectionFallsToFirstCatalogKnownModel() {
        // Nothing matches the ranking → first catalog-known available model.
        let available = ["some-unknown-model", "totally-unknown-too", "gpt-4.1-nano"]
        let best = KnownModelCatalog.bestModel(
            from: available,
            ranking: ["gpt-5.6"],
            in: KnownModelCatalog.entries
        )
        #expect(best == "gpt-4.1-nano")
    }

    @Test func selectionFallsToFirstAvailableWhenNothingKnown() {
        let best = KnownModelCatalog.bestModel(
            from: ["unknown-a", "unknown-b"],
            ranking: [],
            in: KnownModelCatalog.entries
        )
        #expect(best == "unknown-a")
    }

    @Test func selectionReturnsNilForEmptyList() {
        #expect(KnownModelCatalog.bestModel(
            from: [],
            ranking: ["gpt-5.6"],
            in: KnownModelCatalog.entries
        ) == nil)
    }

    // MARK: - Relay auto-select pins (current product decisions)

    /// The post-Berget relay serves exactly these five canonical models, and
    /// auto-select must prefer GLM 5.3 with GLM 5.2 as the congestion fallback.
    @Test func relayAutoSelectPrefersGlm53OverGlm52() {
        let available = [
            "moonshotai/kimi-k3",
            "z-ai/glm-5.3-flash",
            "mistral/mistral-medium-2604",
            "z-ai/glm-5.2",
            "z-ai/glm-5.3",
        ]
        let best = KnownModelCatalog.bestModel(from: available)
        #expect(best == "z-ai/glm-5.3")
        #expect(KnownModelCatalog
            .bestModel(from: available.dropFirst(4).map { $0 }) == "z-ai/glm-5.3")
    }

    @Test func glm52StillResolvesForBYOKProviders() {
        // z.ai and OpenRouter still serve 5.2; the entry stays for BYOK providers.
        let entry = KnownModelCatalog.lookup("z-ai/glm-5.2")
        #expect(entry?.displayName == "GLM 5.2")
        #expect(entry?.supportsVision == false)
    }

    @Test func glm53FamilyCapabilities() {
        // Flash is the multimodal one; 5.3 is text-only.
        #expect(KnownModelCatalog.lookup("z-ai/glm-5.3-flash")?.supportsVision == true)
        #expect(KnownModelCatalog.lookup("z-ai/glm-5.3")?.supportsVision == false)
    }

    @Test func kimiK3Capabilities() {
        let entry = KnownModelCatalog.lookup("moonshotai/kimi-k3")
        #expect(entry?.displayName == "Kimi K3")
        #expect(entry?.family == .moonshot)
        #expect(entry?.contextWindow == 1_048_576)
        #expect(entry?.supportsVision == true)
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

    // MARK: - Fixture builder

    /// Metadata beyond `pattern`/`aliases` is irrelevant to matching rules, so
    /// only the display name distinguishes fixtures.
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
}

@Suite("Best-model selection")
struct BestModelTests {
    @Test("Ranking beats list position")
    func rankingBeatsListPosition() {
        // glm-5.3 outranks glm-5.2 in the preference ranking.
        #expect(KnownModelCatalog
            .bestModel(from: ["z-ai/glm-5.2", "z-ai/glm-5.3"]) == "z-ai/glm-5.3")
        #expect(KnownModelCatalog
            .bestModel(from: ["z-ai/glm-5.3", "z-ai/glm-5.2"]) == "z-ai/glm-5.3")
    }

    @Test("The catalog's top entry wins over anything else")
    func catalogTopWins() {
        #expect(
            KnownModelCatalog.bestModel(from: ["z-ai/glm-5.3", "claude-sonnet-5", "gpt-5.6"])
                == "claude-sonnet-5"
        )
    }

    @Test("Unranked models sort last but still resolve")
    func unknownRanksLast() {
        let models = ["totally-unknown-model", "gpt-5.6"]
        #expect(KnownModelCatalog.bestModel(from: models) == "gpt-5.6")
        #expect(
            KnownModelCatalog.bestModel(from: ["totally-unknown-model"]) == "totally-unknown-model"
        )
    }

    @Test("Empty input is nil")
    func emptyIsNil() {
        #expect(KnownModelCatalog.bestModel(from: []) == nil)
    }
}
