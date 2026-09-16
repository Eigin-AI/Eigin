import Foundation
import Speech

/// Both SpeechAnalyzer result types share `text` + `isFinal` but `text` is not
/// on the protocol. This small conformance lets us iterate results generically.
protocol TranscriberResult {
    var text: AttributedString { get }
    var isFinal: Bool { get }
}

extension SpeechTranscriber.Result: TranscriberResult {}
extension DictationTranscriber.Result: TranscriberResult {}
