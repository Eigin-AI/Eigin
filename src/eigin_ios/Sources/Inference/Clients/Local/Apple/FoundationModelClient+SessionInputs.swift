import Foundation
import FoundationModels

struct SessionInputs {
    let instructions: String?
    let prompt: String
    let chatKey: String
}

@MainActor
func buildSessionInputs(from messages: [ChatMessage]) -> SessionInputs {
    var systemParts: [String] = []
    var lastUserMessage: String?
    var firstUserContent: String?

    for message in messages {
        if message.role == "system" {
            if let content = message.content, !content.isEmpty {
                systemParts.append(content)
            }
            continue
        }
        if message.role == "user", let content = message.content, !content.isEmpty {
            if firstUserContent == nil {
                firstUserContent = stripSystemHint(content)
            }
            lastUserMessage = content
        }
    }

    let instructions = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
    let prompt = lastUserMessage ?? "Hello"

    let normalizedInstructions = (instructions ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedFirstUser = (firstUserContent ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let keySource = normalizedInstructions + "|" + normalizedFirstUser
    let chatKey = String(keySource.hashValue)

    return SessionInputs(instructions: instructions, prompt: prompt, chatKey: chatKey)
}

private func stripSystemHint(_ text: String) -> String {
    guard let rangeStart = text.range(of: "<system_hint>"),
          let rangeEnd = text.range(
              of: "</system_hint>",
              range: rangeStart.lowerBound ..< text.endIndex
          )
    else { return text }
    var result = text
    result.removeSubrange(rangeStart.lowerBound ..< rangeEnd.upperBound)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
