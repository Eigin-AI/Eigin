import Foundation

// MARK: - Math blocks

struct MathState {
    var inBlock = false
    var content = ""

    mutating func open() {
        inBlock = true
        content = ""
    }

    /// True when the line is the closing `$$`.
    func closes(with line: String) -> Bool {
        line.contains("$$")
            && line.replacingOccurrences(of: "$$", with: "")
            .trimmingCharacters(in: .whitespaces).isEmpty
    }

    mutating func claim(_ line: String) {
        content += (content.isEmpty ? "" : "\n") + line
    }
}

extension BlockSplitter {
    mutating func flushMath() {
        guard !math.content.isEmpty else {
            math = MathState()
            return
        }
        append(.math, text: math.content)
        math = MathState()
    }
}
