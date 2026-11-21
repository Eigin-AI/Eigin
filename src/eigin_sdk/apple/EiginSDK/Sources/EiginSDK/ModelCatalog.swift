import EiginSDKBindings

public extension EiginSDK {
    /// Embedded curated model knowledge, preferences, and model-specific policy.
    enum ModelCatalog {
        /// Portable metadata returned by catalog lookup.
        public typealias Entry = CatalogModelEntry
        /// Identity resolution, including alias and version suffix.
        public typealias Match = CatalogModelMatch
        /// Broad catalog family, independent of inference adapters.
        public typealias Family = CatalogModelFamily
        /// Shared reasoning wire vocabulary.
        public typealias Effort = CatalogReasoningEffort
        /// Verified effort policy for a model and endpoint.
        public typealias ReasoningControl = CatalogReasoningControl

        private static let catalog = EiginSDKBindings.ModelCatalog.defaultCatalog()

        /// Ordered curated entries.
        public static var entries: [Entry] {
            catalog.entries()
        }

        /// Best-first offered-ID patterns.
        public static var preferenceRanking: [String] {
            catalog.preferenceRanking()
        }

        /// Relative output-cost thresholds.
        public static var costTerciles: (lower: Double, upper: Double) {
            let value = catalog.costTerciles()
            return (value.lower, value.upper)
        }

        /// Resolves a provider-offered ID.
        public static func lookup(_ model: String) -> Match? {
            catalog.lookup(modelId: model)
        }

        /// Rank of the resolved canonical model, if ranked.
        public static func preferenceRank(_ model: String) -> Int? {
            catalog.preferenceRank(modelId: model).map { Int(clamping: $0) }
        }

        /// Recognized offers, retaining IDs and order.
        public static func knownModels(in available: [String]) -> [String] {
            catalog.knownModels(available: available)
        }

        /// Preferred offer, falling back to first known and then first available.
        public static func bestModel(from available: [String]) -> String? {
            catalog.bestModel(available: available)
        }

        /// Effort policy for verified endpoint/model combinations.
        public static func reasoningControl(model: String, baseURL: String) -> ReasoningControl? {
            catalog.reasoningControl(model: model, baseUrl: baseURL)
        }

        /// Applies verified default/cap policy, otherwise preserving requested effort.
        public static func boundedReasoningEffort(_ effort: Effort?, model: String, baseURL: String) -> Effort? {
            catalog.boundedReasoningEffort(effort: effort, model: model, baseUrl: baseURL)
        }

        /// Conservative image context allowance with saturating arithmetic.
        public static func imageInputBudget(width: Int?, height: Int?, model: String?) -> Int {
            Int(clamping: catalog.imageInputBudget(width: width.map(Int64.init), height: height.map(Int64.init), model: model))
        }
    }
}
