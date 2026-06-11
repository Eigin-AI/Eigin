import Foundation

private let codeBlockCharacterLimit = 3000

func prettyJSON(_ raw: String) -> String? {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(
              withJSONObject: object,
              options: [.prettyPrinted, .sortedKeys]
          ),
          let string = String(data: pretty, encoding: .utf8)
    else { return nil }
    return string
}

func jsonCode(_ raw: String) -> String {
    var content = prettyJSON(raw) ?? raw
    if content.count > codeBlockCharacterLimit {
        content = String(content.prefix(codeBlockCharacterLimit)) + "\n\n… (truncated)"
    }
    return content
}

func jsonLanguage(_ raw: String) -> String? {
    prettyJSON(raw) != nil ? "json" : nil
}
