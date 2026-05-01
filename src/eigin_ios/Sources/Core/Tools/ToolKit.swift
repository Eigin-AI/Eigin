import Foundation

/// A domain-owned group of tools that can be constructed for a given context.
///
/// Each domain defines a kit next to its tool implementations.
/// The app shell composes kits into a `ToolRegistry` without
/// knowing individual tool constructors or service dependencies.
protocol ToolKit {
    /// Capabilities this kit exposes (for permissions UI and catalog).
    static var capabilities: [ToolCapability] { get }

    /// Create all tools this kit provides for the given invocation context.
    @MainActor static func tools(context: ToolContext) -> [any Tool]
}
