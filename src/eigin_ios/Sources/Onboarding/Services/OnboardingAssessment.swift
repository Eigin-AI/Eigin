import Foundation

/// A side-channel call that silently assesses the onboarding conversation,
/// running in parallel with it. Given the transcript so far, it reports what the
/// agent has learned, the user's mood, and how ready the agent is to wrap up.
///
/// The result drives the avatar's fill, the per-turn pacing hints, and the
/// turn-budget backstop. It is never shown to the user.
struct OnboardingAssessment {
    enum Sentiment: String, Equatable {
        case engaged
        case neutral
        case reluctant
    }

    struct Result: Equatable {
        var knowsUser: Bool
        var knowsValues: Bool
        var knowsIdentity: Bool
        var sentiment: Sentiment
        /// How ready the agent is to wrap up and introduce itself, 0...1.
        var readiness: Double

        /// What the agent still needs to establish, in plain language.
        var missing: [String] {
            var items: [String] = []
            if !knowsUser { items.append("who they are and what matters to them") }
            if !knowsValues { items.append("the shared values to build on") }
            if !knowsIdentity { items.append("a name and identity for yourself") }
            return items
        }

        /// The fill target for the avatar, biased so identity completes the ring.
        var fillTarget: Double {
            // Setup screens already filled to ~0.5; the conversation drives the rest.
            let base = 0.5
            return base + (1 - base) * readiness
        }

        static let empty = Result(
            knowsUser: false,
            knowsValues: false,
            knowsIdentity: false,
            sentiment: .neutral,
            readiness: 0
        )
    }

    let chatService: ChatService

    /// Assesses the conversation so far. Falls back to an empty result if the
    /// model returns nothing parseable, so the conversation never blocks on it.
    func run(
        transcript: [ChatMessage],
        baseURL: String,
        providerID: UUID,
        model: String
    ) async throws -> Result {
        let lines = transcript
            .map { "\($0.role): \($0.content ?? "")" }
            .joined(separator: "\n")

        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: Self.systemPrompt),
            ChatMessage(
                role: "user",
                content: "Conversation so far:\n\(lines)\n\nOutput only the JSON."
            ),
        ]

        let stream = try await chatService.chatCompletionStream(
            baseURL: baseURL,
            providerID: providerID,
            messages: messages,
            model: model
        )

        var raw = ""
        for try await chunk in stream {
            raw += chunk
        }

        return Self.parse(raw) ?? .empty
    }

    private static let systemPrompt = """
    You are silently assessing an onboarding conversation between a new AI agent \
    and its user. Based only on what has been said so far, output a single JSON \
    object and nothing else:
    {
      "knows_user": boolean — true if the agent has learned something real about \
    who the user is, their context, or what matters to them,
      "knows_values": boolean — true if there is enough to state the shared \
    values the agent should hold,
      "knows_identity": boolean — true if the agent has proposed a name and \
    identity for itself and the user is comfortable with it,
      "sentiment": one of "engaged", "neutral", "reluctant",
      "readiness": number from 0.0 to 1.0 — how ready the agent is to wrap up and \
    introduce itself
    }
    Output only the JSON object.
    """

    /// Parses the model's reply, tolerating surrounding prose or code fences by
    /// decoding the first complete JSON object found.
    static func parse(_ raw: String) -> Result? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end
        else { return nil }

        let json = String(raw[start ... end])
        guard let data = json.data(using: .utf8),
              let dto = try? JSONDecoder().decode(DTO.self, from: data)
        else { return nil }

        return Result(
            knowsUser: dto.knows_user ?? false,
            knowsValues: dto.knows_values ?? false,
            knowsIdentity: dto.knows_identity ?? false,
            sentiment: dto.sentiment.flatMap(Sentiment.init) ?? .neutral,
            readiness: min(max(dto.readiness ?? 0, 0), 1)
        )
    }

    private struct DTO: Decodable {
        let knows_user: Bool?
        let knows_values: Bool?
        let knows_identity: Bool?
        let sentiment: String?
        let readiness: Double?
    }
}
