import Foundation

/// Replaces native attribution fences without changing surrounding watch reply content.
enum WatchReplyFormatter {
    static func format(
        _ text: String,
        attributionService: any WeatherAttributionServing
    ) async throws -> String {
        let lines = text.components(separatedBy: "\n")
        var fence = CodeFenceState()
        var opening = 0
        var ranges: [ClosedRange<Int>] = []
        for (index, line) in lines.enumerated() {
            if fence.inFence {
                if fence.closes(with: line) {
                    if fence.language == "eigin",
                       EiginBlock.parse(fence.content) == .attribution(source: .appleWeather)
                    {
                        ranges.append(opening ... index)
                    }
                    _ = fence.flush()
                } else {
                    fence.claim(line)
                }
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    opening = index
                    fence.open(line, trimmed: trimmed)
                }
            }
        }
        guard !ranges.isEmpty else { return text }
        let attribution = try await attributionService.load()
        var result = lines
        // Reverse replacement preserves indexes; only the first marker needs legal text.
        for (index, range) in ranges.enumerated().reversed() {
            let replacement = index == 0
                ? ["\(Localized.Weather.Attribution.provider)\n\(attribution.legalText)"] : []
            result.replaceSubrange(range, with: replacement)
        }
        return result.joined(separator: "\n")
    }
}
