/// Steps in the first-launch onboarding flow.
///
/// The setup steps (`welcome`...`inference`) share the persistent avatar via
/// ``OnboardingScaffold``. `conversation` is the chat phase.
enum OnboardingStep: String {
    case welcome
    case name
    case priority
    case inference
    case conversation

    /// Coarse fill for the persistent avatar during setup. The conversation
    /// phase drives the fill the rest of the way from the assessment.
    var avatarProgress: Double {
        switch self {
        case .welcome: 0.05
        case .name: 0.18
        case .priority: 0.3
        case .inference: 0.4
        case .conversation: 0.5
        }
    }

    /// Whether this step is part of the avatar-backed setup sequence.
    var isSetupScreen: Bool {
        switch self {
        case .welcome, .name, .priority, .inference: true
        case .conversation: false
        }
    }
}
