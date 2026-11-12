import EiginSDK

/// Preserves app presentation and retry policy for SDK Responses failures.
enum ResponsesSDKConversion {
    static func error(_ error: any Error) -> any Error {
        guard let failure = error as? EiginSDK.Experimental.Inference.Failure else { return error }
        switch failure {
        case .SubscriptionPlanNotEligible: return ResponsesAPIError.planNotEligible
        case .SubscriptionUsageLimitExceeded: return ResponsesAPIError.usageLimitExceeded
        case .SubscriptionInvalidUser: return ResponsesAPIError.invalidUser
        case .SubscriptionUsageUnavailable: return ResponsesAPIError.usageUnavailable
        case .SubscriptionUnsupportedCapability(let param): return ResponsesAPIError
            .unsupportedCapability(param: param)
        case .Http(let status, let body): return ResponsesAPIError.httpError(
                Int(status),
                body: body
            )
        case .Interrupted, .LimitExceeded: return ResponsesAPIError.interruptedStream
        case .InvalidData, .InvalidUrl, .Busy: return ResponsesAPIError.invalidResponse
        default: return InferenceSDKConversion.error(error)
        }
    }
}
