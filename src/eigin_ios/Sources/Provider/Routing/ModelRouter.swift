import Foundation

/// Chooses which model runs a turn, and what to do when one misbehaves.
///
/// The provider is the user's choice. The one exception is being offline, where the
/// router drops to an on-device model if the user has one ready. Within a provider,
/// model choice belongs to the router whenever the agent is in auto mode.
protocol ModelRouter: Sendable {
    /// The route for a coming turn. Decided before the turn is built, because the prompt
    /// and tool registry are sized from whatever comes back.
    func resolve(_ request: RouteRequest) async -> ResolvedRoute

    /// Records how one stream attempt went.
    func record(_ attempt: AttemptOutcome) async

    /// A route worth retrying on, always on the request's own provider. Nil surfaces the
    /// error to the user.
    func retry(after error: Error, request: RouteRequest) async -> ResolvedRoute?

    /// Whether any healthy candidate could meet the request's requirements. For UI that
    /// decides before a turn exists, like whether to offer the attachment button.
    func canSatisfy(_ request: RouteRequest) async -> Bool
}

// MARK: - Inputs

/// A provider flattened out of SwiftData so routing stays free of persistence.
struct RoutingProvider: Sendable, Equatable {
    let id: UUID
    let name: String
    let baseURL: String
    /// Every model the provider currently serves — the fetched catalogue, kept fresh by
    /// ``ProviderModelRefresher``.
    let availableModels: [String]
    /// The models the user left switched on, their preferred subset of
    /// ``availableModels``. Auto routing treats this as the offer, so it never picks a
    /// model the user turned off. Empty for legacy providers seeded before the field
    /// existed; both cases fall back to the full catalogue.
    let enabledModels: [String]

    init(
        id: UUID,
        name: String,
        baseURL: String,
        availableModels: [String],
        enabledModels: [String] = []
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.availableModels = availableModels
        self.enabledModels = enabledModels
    }

    var isLocal: Bool {
        ProviderPreset.isLocal(baseURL)
    }
}

/// Where the agent is now, what the turn needs, and what it has to choose from.
struct RouteRequest: Sendable {
    /// The provider the user chose.
    let currentProviderID: UUID
    /// The agent's model, and the starting point for stickiness.
    let currentModel: String
    /// False when the user pinned a model, making routing a no-op.
    let isAuto: Bool
    let requirements: RouteRequirements
    let providers: [RoutingProvider]

    var currentProvider: RoutingProvider? {
        providers.first { $0.id == currentProviderID }
    }
}

/// What a turn needs from a model. Also where a request-type hint would go if we later
/// route quick requests differently from thoughtful ones.
struct RouteRequirements: Sendable, Equatable {
    /// Hard: a model that cannot call tools is not an agent.
    var needsToolCalling: Bool = true
    /// Soft: preferred when the turn carries images. A text-only model still works, since
    /// ``MessagePipeline`` strips the images and tells the model why.
    var needsVision: Bool = false
    /// Size of the prompt already built, set on the retry path where compaction cannot
    /// run again. A candidate must fit this *plus its own output reservation*, so the
    /// bar moves with the model rather than a flat figure that no small model could
    /// ever clear.
    var promptTokens: Int?

    init(needsToolCalling: Bool = true, needsVision: Bool = false, promptTokens: Int? = nil) {
        self.needsToolCalling = needsToolCalling
        self.needsVision = needsVision
        self.promptTokens = promptTokens
    }
}

// MARK: - Outputs

/// Where a turn should run, and why that differs from where the agent was.
struct ResolvedRoute: Sendable, Equatable {
    let providerID: UUID
    let baseURL: String
    let model: String
    /// Nil when nothing moved.
    let change: RouteChange?

    /// Whether this route stays on the user's provider. Only those are written back to
    /// the agent, so an offline detour never overwrites their choice.
    func staysOn(providerID id: UUID) -> Bool {
        providerID == id
    }
}

/// Why the router moved the agent. Whether any of it is worth telling the user, and in
/// what words, is the view layer's call.
enum RouteChange: Sendable, Equatable {
    /// Dropped to an on-device model because the network is unreachable.
    case offlineFallback(previousProvider: String)
    /// The model is gone from the provider's catalog.
    case modelRetired(previous: String)
    /// The model still exists but is erroring or too slow.
    case modelDegraded(previous: String, reason: DegradationReason)
    /// Enough idle time passed to clear health and reset preference to the top.
    case sessionReset(previous: String)
}

enum DegradationReason: Sendable, Equatable {
    case errors
    case slowFirstToken
    case slowThroughput
}

/// How one stream attempt went, reported after the stream ends.
struct AttemptOutcome: Sendable {
    enum Result: Sendable {
        case succeeded
        case failed(RoutingFailure)
        /// The user stopped the turn, which says nothing about the model.
        case cancelled
    }

    let providerID: UUID
    let model: String
    /// Nil when the stream failed before producing anything.
    let timeToFirstToken: Duration?
    /// Nil when too little was produced to be meaningful.
    let tokensPerSecond: Double?
    let duration: Duration
    let result: Result
}

/// The model-relevant shape of a failure, classified once at the boundary.
enum RoutingFailure: Sendable, Equatable {
    /// Unknown to the provider: retired, renamed, or never existed.
    case modelNotFound
    /// The provider is struggling: 5xx, 429, overloaded, upstream error.
    case providerOverloaded
    /// No usable network path.
    case offline
    /// The user's to fix: auth, credits, malformed request.
    case notTheModelsFault
    /// No first token within the hard ceiling, indistinguishable from a hang.
    case timedOut
}
