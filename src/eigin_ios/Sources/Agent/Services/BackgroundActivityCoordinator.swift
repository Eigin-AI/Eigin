import Foundation

/// Admits one opportunity and bounds the number of active activities within it.
@MainActor
final class BackgroundActivityCoordinator {
    private(set) var isRunning = false

    /// Returns nil when another opportunity owns execution. Results arrive as each activity
    /// finishes.
    func run<ID: Sendable, Output: Sendable>(
        activities: [ID], limit: Int,
        execute: @escaping @MainActor @Sendable (ID) async -> Output,
        onResult: @MainActor (ID, Output) async -> Void
    ) async -> [Output]? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        return await withTaskGroup(of: (ID, Output).self) { group in
            var next = 0
            func enqueue() {
                guard !Task.isCancelled, next < activities.count else { return }
                let activity = activities[next]
                next += 1
                group.addTask {
                    let output = await execute(activity)
                    return (activity, output)
                }
            }
            for _ in 0 ..< min(max(1, limit), activities.count) {
                enqueue()
            }
            var results: [Output] = []
            while let (activity, result) = await group.next() {
                results.append(result)
                await onResult(activity, result)
                enqueue()
            }
            return results
        }
    }
}
