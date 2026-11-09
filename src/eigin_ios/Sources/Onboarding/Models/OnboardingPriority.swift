import SwiftUI

/// What the user is hoping to get from a personal AI, chosen during onboarding.
///
/// Persisted and seeded into the first conversation so the agent can shape itself
/// around it. The first three are concrete, broadly relatable use cases; the
/// fourth is an open "something else" the agent picks up on later in the chat.
/// Each case carries the copy shown on its choice card.
enum OnboardingPriority: String, CaseIterable, Identifiable {
    case stayOnTop, getStuffDone, clarity, somethingElse

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .stayOnTop: Localized.Onboarding.Priority.StayOnTop.title
        case .getStuffDone: Localized.Onboarding.Priority.GetStuffDone.title
        case .clarity: Localized.Onboarding.Priority.Clarity.title
        case .somethingElse: Localized.Onboarding.Priority.SomethingElse.title
        }
    }

    var explainer: String {
        switch self {
        case .stayOnTop: Localized.Onboarding.Priority.StayOnTop.explainer
        case .getStuffDone: Localized.Onboarding.Priority.GetStuffDone.explainer
        case .clarity: Localized.Onboarding.Priority.Clarity.explainer
        case .somethingElse: Localized.Onboarding.Priority.SomethingElse.explainer
        }
    }

    /// How the agent is told about this choice when the conversation begins.
    var conversationSeed: String {
        switch self {
        case .stayOnTop:
            Prompt.Onboarding.Priority.stayOnTop
        case .getStuffDone:
            Prompt.Onboarding.Priority.getStuffDone
        case .clarity:
            Prompt.Onboarding.Priority.clarity
        case .somethingElse:
            Prompt.Onboarding.Priority.somethingElse
        }
    }

    /// Cave-painting illustrations: a tree for structure, a many-armed person
    /// for action, a ghost for reflection, and a bird for open horizons.
    var illustration: Image {
        switch self {
        case .stayOnTop: Iconography.Illustration.tree
        case .getStuffDone: Iconography.Illustration.person1
        case .clarity: Iconography.Illustration.ghost
        case .somethingElse: Iconography.Illustration.bird
        }
    }
}
