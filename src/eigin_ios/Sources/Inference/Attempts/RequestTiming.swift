import EiginSDK
import Foundation

enum RequestTiming {
    static func log(
        prep: Duration?,
        modelTTFT: Duration?,
        result: EiginSDK.Experimental.Routing.Result
    ) {
        let outcome = switch result {
        case .succeeded: "done"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
        func format(_ duration: Duration?) -> String {
            guard let duration else { return "n/a" }
            let seconds = Double(duration.components.seconds) +
                Double(duration.components.attoseconds) / 1e18
            return String(format: "%.2fs", seconds)
        }
        let perceived: Duration? = {
            guard let prep, let modelTTFT else { return nil }
            return prep + modelTTFT
        }()
        AppLogger.info(
            "Turn timing (\(public: outcome)): prep send→dispatch \(public: format(prep)), model TTFT \(public: format(modelTTFT)), perceived TTFT \(public: format(perceived))",
            category: .chat
        )
    }
}
