import Foundation

/// Serializes background knowledge operations without holding model requests open.
@MainActor
final class KnowledgeOperationCoordinator {
    static let shared = KnowledgeOperationCoordinator()
    private var busy = false
    private var waiters: [(UUID, CheckedContinuation<Bool, Never>)] = []

    func perform<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        if busy {
            let id = UUID()
            let acquired = await withTaskCancellationHandler {
                await withCheckedContinuation { waiters.append((id, $0)) }
            } onCancel: {
                Task { @MainActor in
                    guard let index = self.waiters.firstIndex(where: { $0.0 == id }) else { return }
                    self.waiters.remove(at: index).1.resume(returning: false)
                }
            }
            guard acquired else { throw CancellationError() }
        } else {
            busy = true
        }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().1.resume(returning: true) }
        }
        try Task.checkCancellation()
        return try await operation()
    }
}
