import EiginSDKBindings
import Foundation

/// Adapts asynchronous platform effects to synchronous UniFFI callbacks.
final class RequestHostAdapter: RequestHost, @unchecked Sendable {
    func reported(report: RequestReport?, result: RoutingResult) {
        services.reported(report, result)
    }

    private typealias Inference = EiginSDK.Experimental.Inference
    private let services: Inference.RequestServices
    private let lock = NSLock()
    private var operations: [UInt64: RequestWork] = [:]
    private var candidates: [UInt64: RequestSessionSlot] = [:]

    init(services: EiginSDK.Experimental.Inference.RequestServices) {
        self.services = services
    }

    private func run(_ id: UInt64, body: @escaping @Sendable () async -> Void) {
        let work = RequestWork()
        lock.withLock { operations[id] = work }
        work.launch { [weak self] in
            await body()
            _ = self?.lock.withLock { self?.operations.removeValue(forKey: id) }
        }
    }

    func validate(operationId: UInt64, candidateId _: UInt64, model: String, completion: RequestUnitCallback) {
        run(operationId) { [services] in
            do {
                try await services.validate(model)
                try Task.checkCancellation()
                _ = completion.succeed()
            } catch { completion.fail(error: requestHostError(error)) }
        }
    }

    func startCandidate(operationId: UInt64, candidateId: UInt64, model: String, effort: CatalogReasoningEffort?, completion: RequestUnitCallback) {
        let slot = RequestSessionSlot()
        let previous = lock.withLock { candidates.updateValue(slot, forKey: candidateId) }
        previous?.cancel()
        run(operationId) { [services] in
            do {
                let session = try await services.open(model, effort)
                if Task.isCancelled {
                    session.cancel()
                    throw CancellationError()
                }
                guard slot.install(session) else { throw CancellationError() }
                if !completion.succeed() { slot.cancel() }
            } catch {
                slot.cancel()
                completion.fail(error: requestHostError(error))
            }
        }
    }

    func read(operationId: UInt64, candidateId: UInt64, completion: RequestEventCallback) {
        guard let slot = lock.withLock({ candidates[candidateId] }) else {
            completion.fail(error: .Inference(.Cancelled))
            return
        }
        run(operationId) {
            do {
                let event = try await slot.next()
                try Task.checkCancellation()
                _ = completion.succeed(event: event)
            } catch { completion.fail(error: requestHostError(error)) }
        }
    }

    func refreshCatalog(operationId: UInt64, providerId: String, completion: RequestInventoryCallback) {
        run(operationId) { [services] in
            let inventory = await services.refreshCatalog(providerId)
            _ = completion.succeed(inventory: inventory)
        }
    }

    func refreshHealth(operationId: UInt64, providerId: String, completion: RequestHealthCallback) {
        run(operationId) { [services] in
            let observations = await services.refreshHealth(providerId)
            _ = completion.succeed(observations: observations)
        }
    }

    func cancelOperation(operationId: UInt64) {
        lock.withLock { operations.removeValue(forKey: operationId) }?.cancel()
    }

    func cancelCandidate(candidateId: UInt64) {
        lock.withLock { candidates.removeValue(forKey: candidateId) }?.cancel()
    }

    func wallTime() -> Double {
        services.now().timeIntervalSince1970
    }
}
