import Foundation

/// Tells the model which interaction mode the user is currently in.
///
/// Stateful: the first time a mode is rendered in a session (or whenever the
/// mode changes) the source emits the full behavioural guidance for that mode.
/// On subsequent turns with the same mode it emits a shorter reminder so the
/// model stays oriented without diluting attention on repetition.
@MainActor
final class InteractionModeSource: SystemHintSource {
    let title = "Interaction mode"

    private var lastMode: InteractionMode?

    func render(_ input: SystemHintInput) async -> String? {
        defer { lastMode = input.mode }
        let isFirstOrChanged = (lastMode == nil) || (lastMode != input.mode)
        return isFirstOrChanged ? input.mode.fullDescription : input.mode.shortReminder
    }
}
