import Foundation
import SwiftUI

@Observable
@MainActor
final class StreamingBlockSplitter {
    private weak var throttler: (any StreamThrottling)?

    /// All blocks - both sealed and currently streaming.
    /// The last block is the "active" one being written to.
    private(set) var allBlocks: [ContentBlock] = []

    private var messageID: String = ""
    private var observationTask: Task<Void, Never>?

    init(throttler: any StreamThrottling) {
        self.throttler = throttler
    }

    func setMessageID(_ id: String) {
        messageID = id
    }

    func start() {
        allBlocks = []

        observationTask?.cancel()
        observationTask = Task { [weak self] in
            await self?.observeThrottler()
        }
    }

    func seal() {
        observationTask?.cancel()
        observationTask = nil
        // Seal just marks the end of streaming - allBlocks already contains everything
    }

    func reset() {
        observationTask?.cancel()
        observationTask = nil

        allBlocks = []
    }

    private func observeThrottler() async {
        guard let throttler else { return }

        while !Task.isCancelled {
            let currentText = throttler.displayedText
            process(newText: currentText)

            withObservationTracking {
                _ = throttler.displayedText
            } onChange: {
                // Will trigger next loop iteration
            }

            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func process(newText: String) {
        guard !newText.isEmpty else {
            allBlocks = []
            return
        }

        let newBlocks = ContentBlock.split(newText, messageID: messageID)
        guard !newBlocks.isEmpty else { return }

        // Always replace with full set - blocks maintain stable IDs by index
        allBlocks = newBlocks
    }
}
