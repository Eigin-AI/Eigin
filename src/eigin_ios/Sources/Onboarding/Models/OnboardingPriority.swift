import SwiftUI

/// What the user is hoping to get from a personal AI, chosen during onboarding.
///
/// Persisted and seeded into the first conversation so the agent can shape itself
/// around it. The first three are concrete, broadly relatable use cases; the
/// fourth is an open "something else" the agent picks up on later in the chat.
/// Each case carries the copy shown on its choice card.
enum OnboardingPriority: String, CaseIterable, Identifiable {
    case stayOnTop, people, clarity, somethingElse

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .stayOnTop: Localized.Onboarding.Priority.StayOnTop.title
        case .people: Localized.Onboarding.Priority.People.title
        case .clarity: Localized.Onboarding.Priority.Clarity.title
        case .somethingElse: Localized.Onboarding.Priority.SomethingElse.title
        }
    }

    var explainer: String {
        switch self {
        case .stayOnTop: Localized.Onboarding.Priority.StayOnTop.explainer
        case .people: Localized.Onboarding.Priority.People.explainer
        case .clarity: Localized.Onboarding.Priority.Clarity.explainer
        case .somethingElse: Localized.Onboarding.Priority.SomethingElse.explainer
        }
    }

    /// How the agent is told about this choice when the conversation begins.
    var conversationSeed: String {
        switch self {
        case .stayOnTop:
            "staying on top of their daily life: their schedule, errands, and the things that pile up"
        case .people:
            "the people they love: keeping up with family and friends and showing up for them"
        case .clarity:
            "thinking things through: talking things out and working through decisions"
        case .somethingElse:
            "something they haven't pinned down yet, so stay open and ask what they're hoping for"
        }
    }

    /// Illustration icon mapped from an abstract feel. The images are
    /// cave-painting style abstractions: a tree for structure, figures for
    /// connection, a ghost for reflection, a bird for open horizons.
    var illustration: Image {
        switch self {
        case .stayOnTop: Iconography.Illustration.tree
        case .people: Iconography.Illustration.person2
        case .clarity: Iconography.Illustration.ghost
        case .somethingElse: Iconography.Illustration.bird
        }
    }
}
