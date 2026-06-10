import SwiftUI

// MARK: - Option set (presented by the agent)

/// A set of options presented to the user by the agent.
struct OptionSet: Identifiable, Equatable {
    let id: String // tool call ID
    let question: String?
    let options: [OptionItem]
}

// MARK: - Single option

/// A single selectable option shown on an `AppVisualCard`.
struct OptionItem: Identifiable, Equatable {
    let label: String // short title, returned when selected
    let description: String // 1-2 sentence explainer
    let category: OptionCategory? // abstract feel → determines visual icon

    var id: String {
        label
    }
}

// MARK: - Abstract category

/// High-level abstract option categories that map to visual assets (cave-painting-style
/// icons: bird, plant, person, geometric shapes, etc.).
///
/// The agent picks a category that describes the *feel* or *nature* of the choice,
/// and the UI maps it to an icon from our visual library.
enum OptionCategory: String, CaseIterable {
    case focus
    case explore
    case create
    case organise
    case care
    case connect
    case decide
    case move
    case grow
    case play
    case reflect
    case prepare
    case celebrate
    case learn
    case build
    case rest
    case challenge
    case share
    case discover
    case express
}

/// Result of an option interaction.
enum OptionSelection {
    case selected(label: String)
    case dismissed
}

// MARK: - Handler type

typealias OptionsHandler = @Sendable @MainActor (OptionSet) async -> OptionSelection

// MARK: - Category → illustration icon

extension OptionCategory {
    /// Illustration icon mapped from the abstract category.
    var image: Image {
        switch self {
        case .focus: Iconography.Illustration.circle
        case .explore: Iconography.Illustration.bird
        case .create: Iconography.Illustration.ink1
        case .organise: Iconography.Illustration.tree
        case .care: Iconography.Illustration.flower
        case .connect: Iconography.Illustration.person2
        case .decide: Iconography.Illustration.volcano
        case .move: Iconography.Illustration.wave
        case .grow: Iconography.Illustration.root
        case .play: Iconography.Illustration.butterfly
        case .reflect: Iconography.Illustration.ghost
        case .prepare: Iconography.Illustration.mountain
        case .celebrate: Iconography.Illustration.ink2
        case .learn: Iconography.Illustration.cell
        case .build: Iconography.Illustration.crab
        case .rest: Iconography.Illustration.moon
        case .challenge: Iconography.Illustration.octopus
        case .share: Iconography.Illustration.person1
        case .discover: Iconography.Illustration.ghost
        case .express: Iconography.Illustration.cactus
        }
    }
}
