import Foundation

/// A deduplicated edge between two nodes in the knowledge graph.
///
/// Edges are undirected for display purposes — direction details are
/// available in the detail sheet. Bidirectional connections (A->B and B->A)
/// are collapsed into a single edge.
struct GraphEdge: Identifiable, Equatable {
    /// Canonical edge ID: sorted pair of node IDs.
    let id: String
    /// First node ID.
    let sourceID: String
    /// Second node ID.
    let targetID: String

    init(from sourceID: String, to targetID: String) {
        // Canonical ordering for deduplication.
        if sourceID < targetID {
            self.sourceID = sourceID
            self.targetID = targetID
        } else {
            self.sourceID = targetID
            self.targetID = sourceID
        }
        id = "\(self.sourceID)->\(self.targetID)"
    }
}
