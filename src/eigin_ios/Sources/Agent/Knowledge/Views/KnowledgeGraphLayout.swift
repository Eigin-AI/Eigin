import SwiftUI

/// Gallery slot layouts. Positions describe the whole circle-and-label node.
enum KnowledgeGraphLayout {
    static func slots(count: Int, size: CGSize) -> [CGPoint] {
        if size.height < 4 * Spacing.n48, size.width >= 5 * Spacing.n88, count <= 4 {
            let shortSlots: [(CGFloat, CGFloat)] = switch count {
            case 0: []
            case 1: [(20, 50)]
            case 2: [(20, 50), (80, 50)]
            case 3: [(10, 35), (28, 65), (80, 50)]
            default: [(10, 35), (28, 65), (72, 35), (90, 65)]
            }
            return shortSlots.map { position(x: $0.0, y: $0.1, size: size) }
        }
        let slots: [(CGFloat, CGFloat)] = switch count {
        case 0: []
        case 1: [(50, 14)]
        case 2: [(50, 14), (50, 86)]
        case 3: [(50, 14), (18, 76), (82, 76)]
        case 4: [(18, 24), (82, 24), (18, 76), (82, 76)]
        case 5: [(50, 14), (18, 30), (82, 30), (18, 76), (82, 76)]
        default: [(18, 30), (50, 18), (82, 30), (18, 70), (50, 82), (82, 70)]
        }
        return slots.map { x, y in
            let rotated = size.width > size.height ? (y, 100 - x) : (x, y)
            return position(x: rotated.0, y: rotated.1, size: size)
        }
    }

    static func position(x: CGFloat, y: CGFloat, size: CGSize) -> CGPoint {
        let inset: CGFloat = size.height < 300 ? 48 : 56
        return CGPoint(
            x: size.width * x / 100,
            y: max(inset, min(size.height - inset, size.height * y / 100))
        )
    }
}

/// Stable identity lets retained nodes move without unmounting or cross-fading.
struct KnowledgeGraphPlacement: Identifiable, Equatable {
    let entity: FirmEntity
    let position: CGPoint
    let isFocus: Bool
    let name: String

    init(entity: FirmEntity, position: CGPoint, isFocus: Bool) {
        self.entity = entity
        self.position = position
        self.isFocus = isFocus
        name = KnowledgePresentation(entity).name
    }

    var id: String {
        entity.id
    }
}

/// Cancellable remove/move/introduce choreography; SwiftUI interpolates each change.
@Observable
@MainActor
final class KnowledgeGraphTransition {
    private(set) var shown: [KnowledgeGraphPlacement] = []
    private(set) var visible: Set<String> = []
    private(set) var revealed: Set<String> = []
    private(set) var labelsMounted = true
    private(set) var preservedLabels: Set<String> = []
    private(set) var linesVisible = false
    private(set) var isTransitioning = false
    private var generation = 0

    /// Drive from `.task(id: placements)`; cancellation leaves a consistent next starting point.
    func update(_ target: [KnowledgeGraphPlacement], reducedMotion: Bool) async {
        generation += 1
        let ticket = generation
        isTransitioning = true
        if reducedMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                shown = target
                visible = Set(target.map(\.id))
                revealed = visible
                labelsMounted = true
                preservedLabels = []
                linesVisible = true
                isTransitioning = false
            }
            return
        }
        let targetIDs = Set(target.map(\.id))
        let departing = shown.filter { !targetIDs.contains($0.id) }
        let retainedIDs = Set(shown.map(\.id)).intersection(targetIDs).intersection(visible)
        let arriving = target.filter { !retainedIDs.contains($0.id) }
        let retained = target.filter { retainedIDs.contains($0.id) }
        let moving = retained.contains { node in
            guard let old = shown.first(where: { $0.id == node.id }) else { return true }
            return old.position != node.position || old.isFocus != node.isFocus
        }
        if departing.isEmpty, arriving.isEmpty, !moving, linesVisible, revealed == targetIDs {
            shown = target
            isTransitioning = false
            return
        }
        preservedLabels = Set(retained.filter { node in
            guard node.isFocus, revealed.contains(node.id),
                  let previous = shown.first(where: { $0.id == node.id }) else { return false }
            return previous.isFocus && previous.position == node.position
        }.map(\.id))
        do {
            // Stationary focus labels stay visible; moving labels leave the render pass.
            withAnimation(.linear(duration: 0.08)) {
                linesVisible = false
                revealed = preservedLabels
            }
            withAnimation(.easeOut(duration: 0.12)) {
                visible.subtract(departing.map(\.id))
            }
            if !shown.isEmpty { try await pause(120, ticket: ticket) }
            labelsMounted = false
            withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.3)) {
                shown = retained
                visible = retainedIDs
            }
            if moving { try await pause(315, ticket: ticket) }
            shown = target
            labelsMounted = true
            // Mount edges and labels hidden before their individual opacity animations.
            try await pause(25, ticket: ticket)
            withAnimation(.linear(duration: 0.12)) {
                revealed = retainedIDs
                linesVisible = true
            }
            try await introduce(arriving, ticket: ticket)
            isTransitioning = false
        } catch {
            if generation == ticket { cancel() }
        }
    }

    /// One timeline drives both circle entry and edge/label reveal, independent of render
    /// callbacks.
    private func introduce(_ nodes: [KnowledgeGraphPlacement], ticket: Int) async throws {
        var events: [(delay: Int, id: String, reveal: Bool)] = []
        var delay = 0
        for node in nodes {
            events.append((delay, node.id, false))
            events.append((delay + 120, node.id, true))
            delay += 25 + jitter(node.id)
        }
        let clock = ContinuousClock()
        let start = clock.now
        for event in events.sorted(by: { $0.delay < $1.delay }) {
            try await clock.sleep(until: start.advanced(by: .milliseconds(event.delay)))
            try check(ticket)
            if event.reveal {
                withAnimation(.linear(duration: 0.12)) { _ = revealed.insert(event.id) }
            } else {
                withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.12)) {
                    _ = visible.insert(event.id)
                }
            }
        }
    }

    func cancel() {
        generation += 1
        isTransitioning = false
    }

    /// Bounded per-node jitter so staggered pops feel organic, like the web
    /// gallery's random addition, but stable across re-entry.
    private func jitter(_ id: String) -> Int {
        Int(UInt(bitPattern: id.hashValue) % 11)
    }

    private func check(_ ticket: Int) throws {
        try Task.checkCancellation()
        if generation != ticket { throw CancellationError() }
    }

    private func pause(_ milliseconds: Int, ticket: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
        try check(ticket)
    }
}
