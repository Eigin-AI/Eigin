@testable import Eigin
import EiginSDK
import Foundation

/// Presents an SDK-owned request to the chat loop and logs accepted-output timing.
@MainActor
final class InferenceAttempt {
    let stream: AsyncThrowingStream<ChatStreamEvent, Error>
    private let request: EiginSDK.Experimental.Inference.Request
    private let dispatchedAt: ContinuousClock.Instant

    init(
        request: EiginSDK.Experimental.Inference.Request,
        errors: RequestHostErrors,
        dispatchedAt: ContinuousClock.Instant
    ) {
        self.request = request
        self.dispatchedAt = dispatchedAt
        stream = AsyncThrowingStream(unfolding: {
            do { return try await request.next().map(InferenceSDKConversion.event) }
            catch { throw errors.restore(error) }
        })
    }

    deinit { request.cancel() }

    func observe(_ event: ChatStreamEvent) {
        do { try request.observeOutput(InferenceSDKConversion.event(event)) }
        catch { AppLogger.error("Request output observation failed", category: .chat) }
    }

    var winningModel: String {
        get throws { try request.selection().model }
    }

    var retryWon: Bool {
        get throws { try request.selection().retryWon }
    }

    @discardableResult
    func report(sentAt: ContinuousClock.Instant?, result: AttemptOutcome.Result) async -> EiginSDK
        .Experimental.Inference.RequestReport?
    {
        do {
            let report = try request.report(RoutingSDKConversion.result(result))
            RequestTiming.log(
                prep: sentAt.map { $0.duration(to: dispatchedAt) },
                modelTTFT: report?.firstTokenSeconds.map { .seconds($0) },
                result: RoutingSDKConversion.result(result)
            )
            return report
        } catch {
            AppLogger.error("Request outcome reporting failed", category: .chat)
            return nil
        }
    }
}
