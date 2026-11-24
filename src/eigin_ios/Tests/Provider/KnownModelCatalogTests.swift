@testable import Eigin
import Foundation
import Testing

/// Behavior tests for ``KnownModelCatalog``.
///
/// Model-specific behavior is covered by rules and invariants over the whole
/// catalog (every pattern/alias resolving, ranking entries resolving, ordering
/// guarantees) with fixture-based matching and selection rules covered in Rust. New catalog entries
/// are automatically covered by the invariants.
@Suite("KnownModelCatalog")
struct KnownModelCatalogTests {
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
        #expect(ProviderPreset.isLocal("local://gemma-4-e2b") == true)
    }

    @Test func isLocalForFutureLocalProvider() {
        #expect(ProviderPreset.isLocal("local://ollama") == true)
    }

    @Test func isLocalFalseForHTTPS() {
        #expect(ProviderPreset.isLocal("https://api.openai.com/v1") == false)
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

    @Test("Provider-prefixed selection follows ranking regardless of input order")
    func prefixedSelectionFollowsRanking() throws {
        let available = KnownModelCatalog.preferenceRanking.map { "provider/\($0)" }
        let preferred = try #require(available.first)
        #expect(KnownModelCatalog.bestModel(from: available) == preferred)
        #expect(KnownModelCatalog.bestModel(from: Array(available.reversed())) == preferred)

        let fallback = Array(available.dropFirst())
        let nextPreferred = try #require(fallback.first)
        #expect(KnownModelCatalog.bestModel(from: Array(fallback.reversed())) == nextPreferred)
    }

    @Test("Empty input is nil")
    func emptyIsNil() {
        #expect(KnownModelCatalog.bestModel(from: []) == nil)
    }
}

// MARK: - Instant variants are ranked (arbitrary ties are unspecified ordering)

extension KnownModelCatalogTests {
    @Test("every entry's pattern appears in the preference ranking")
    func allPatternsAreRanked() {
        for entry in KnownModelCatalog.entries {
            #expect(
                KnownModelCatalog.preferenceRanking.contains(entry.pattern),
                "\(entry.pattern) is missing from preferenceRanking — unranked entries tie and sort arbitrarily"
            )
        }
    }
}
