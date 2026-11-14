import Foundation

/// Durable request selections and user messages carrying the paging notice.
struct ContextPageState: Codable, Equatable {
    var version = 1
    var excludedIDs: Set<String> = []
    var maskedIDs: Set<String> = []
    var hasPaged = false
    var hintedUserIDs: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, excludedIDs, maskedIDs, hasPaged, hintedUserIDs, hintMessageID
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        excludedIDs = try values.decode(Set<String>.self, forKey: .excludedIDs)
        maskedIDs = try values.decode(Set<String>.self, forKey: .maskedIDs)
        hasPaged = try values.decode(Bool.self, forKey: .hasPaged)
        hintedUserIDs = try values.decodeIfPresent(Set<String>.self, forKey: .hintedUserIDs) ?? []
        if let previous = try values.decodeIfPresent(String.self, forKey: .hintMessageID) {
            hintedUserIDs.insert(previous)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(excludedIDs, forKey: .excludedIDs)
        try values.encode(maskedIDs, forKey: .maskedIDs)
        try values.encode(hasPaged, forKey: .hasPaged)
        try values.encode(hintedUserIDs, forKey: .hintedUserIDs)
    }
}
