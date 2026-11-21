import {
  initialize,
  ModelCatalog,
  CatalogModelFamily,
  CatalogReasoningEffort,
} from "../src";

export const catalogTests = {
  async values() {
    await initialize();
    const catalog = ModelCatalog.defaultCatalog();
    const entries = catalog.entries();
    const entry = entries[0];
    if (!entry) throw new Error("Embedded catalog is empty");
    const offered = `provider/${entry.pattern}`;
    const match = catalog.lookup(offered);
    const versioned = catalog.lookup(`${offered}-一`);
    const aliasEntry = entries.find((value) => value.aliases.length > 0);
    const reasoningEntry = entries.find((value) => value.reasoningControl);
    const enumValues = Object.values(CatalogModelFamily);
    return {
      metadataRoundTrips:
        JSON.stringify(match?.entry, stringifyBigint) ===
        JSON.stringify(entry, stringifyBigint),
      familyIsExported: enumValues.includes(entry.family),
      integerLimit: typeof match?.entry.contextWindow === "bigint",
      unknown: catalog.lookup("unknown-test-model") === undefined,
      exactVersion: match?.versionTag === undefined,
      unicodeVersion: versioned?.versionTag,
      alias:
        aliasEntry !== undefined &&
        catalog.lookup(aliasEntry.aliases[0])?.entry.pattern ===
          aliasEntry.pattern,
      optionalControl:
        reasoningEntry !== undefined &&
        catalog.lookup(reasoningEntry.pattern)?.entry.reasoningControl
          ?.fastEffort === reasoningEntry.reasoningControl?.fastEffort,
      rank:
        catalog.preferenceRank(offered) ===
        BigInt(catalog.preferenceRanking().indexOf(entry.pattern)),
      unknownRank: catalog.preferenceRank("unknown-test-model") === undefined,
    };
  },

  async operations() {
    await initialize();
    const catalog = ModelCatalog.defaultCatalog();
    const first = catalog.entries()[0];
    if (!first) throw new Error("Embedded catalog is empty");
    const offered = `provider/${first.pattern}`;
    const offers = ["unknown-test-model", offered];
    const max = 9223372036854775807n;
    return {
      known: catalog.knownModels(offers),
      best: catalog.bestModel(offers),
      offered,
      empty: catalog.bestModel([]) === undefined,
      effort:
        catalog.boundedReasoningEffort(
          CatalogReasoningEffort.Max,
          offered,
          "https://unverified.example",
        ) === CatalogReasoningEffort.Max,
      absentEffort:
        catalog.boundedReasoningEffort(
          undefined,
          offered,
          "https://unverified.example",
        ) === undefined,
      absentControl:
        catalog.reasoningControl(offered, "https://unverified.example") ===
        undefined,
      imageDefaults:
        catalog.imageInputBudget(undefined, undefined, offered) ===
        catalog.imageInputBudget(1024n, 1024n, offered),
      imageOverflow: catalog.imageInputBudget(max, max, offered) === max,
      signedDimensions:
        catalog.imageInputBudget(-1n, 0n, offered) ===
        catalog.imageInputBudget(1n, 1n, offered),
      prices: catalog.costTerciles().lower <= catalog.costTerciles().upper,
    };
  },
};

function stringifyBigint(_key: string, value: unknown): unknown {
  return typeof value === "bigint" ? value.toString() : value;
}

window.catalogTests = catalogTests;
