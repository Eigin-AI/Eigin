import Foundation

/// Picks one intent to focus a background initiative run on, cycling through the
/// active pool instead of leaving topic selection entirely up to the model.
///
/// The model is not a good ranker across runs — it has no memory of which
/// intent it dwelled on recently, so left to "choose the most valuable topic"
/// from the same pool every time, it tends to fixate. This picks
/// deterministically: prefer intents that have never been focused, ranked by
/// relevance; once every active intent has had a turn, cycle back to whichever
/// was focused longest ago.
enum InitiativeIntentRotation {
    /// Result of a rotation decision.
    struct Selection {
        /// The intent to focus this run on, or `nil` if there are no active intents.
        let focus: IntentSnapshot?
        /// The updated focus history to persist, reflecting this selection.
        let history: [UUID]
    }

    /// Chooses the next focus intent and returns the updated history to persist.
    ///
    /// - Parameters:
    ///   - rankedIntents: Active intents, already sorted by relevance (descending).
    ///   - history: Previously-focused intent IDs, ordered oldest to most recent.
    static func select(rankedIntents: [IntentSnapshot], history: [UUID]) -> Selection {
        guard !rankedIntents.isEmpty else {
            return Selection(focus: nil, history: history)
        }

        let activeIDs = Set(rankedIntents.map(\.id))
        // Drop history entries for intents that are no longer active so the
        // rotation window tracks the live set.
        let prunedHistory = history.filter { activeIDs.contains($0) }

        let chosen: IntentSnapshot
        if let neverFocused = rankedIntents.first(where: { !prunedHistory.contains($0.id) }) {
            chosen = neverFocused
        } else {
            // Every active intent has had a turn — pick whichever was focused
            // longest ago (earliest position in history).
            let leastRecentID = prunedHistory.first { activeIDs.contains($0) }
            chosen = rankedIntents.first { $0.id == leastRecentID } ?? rankedIntents[0]
        }

        var updatedHistory = prunedHistory.filter { $0 != chosen.id }
        updatedHistory.append(chosen.id)
        // Cap the window to the live set so it doesn't grow unbounded.
        if updatedHistory.count > activeIDs.count {
            updatedHistory.removeFirst(updatedHistory.count - activeIDs.count)
        }

        return Selection(focus: chosen, history: updatedHistory)
    }
}
