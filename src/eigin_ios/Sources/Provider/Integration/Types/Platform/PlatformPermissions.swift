import CoreLocation
import Foundation

/// Apple Health's permission. Apple Health says what Eigin may save, kind by
/// kind, but never what it may read, so it is never reported as refused: a
/// person who allowed nothing still reads as connected.
struct HealthPermission: PlatformPermission {
    let service: any HealthService

    nonisolated static let reads = [
        PlatformDataKind(
            use: .reads,
            key: "activity",
            name: Localized.Integrations.Platform.Kind.activity
        ),
        PlatformDataKind(
            use: .reads,
            key: "sleep",
            name: Localized.Integrations.Platform.Kind.sleep
        ),
        PlatformDataKind(
            use: .reads,
            key: "nutrition",
            name: Localized.Integrations.Platform.Kind.nutrition
        ),
        PlatformDataKind(
            use: .reads,
            key: "bodyMeasurements",
            name: Localized.Integrations.Platform.Kind.bodyMeasurements
        ),
        PlatformDataKind(
            use: .reads,
            key: "heart",
            name: Localized.Integrations.Platform.Kind.heart
        ),
    ]

    /// Keyed by ``HealthSave`` so what Health reports maps straight onto rows.
    nonisolated static let saves = [
        PlatformDataKind(
            use: .saves,
            key: HealthSave.meals.rawValue,
            name: Localized.Integrations.Platform.Kind.meals
        ),
        PlatformDataKind(
            use: .saves,
            key: HealthSave.sleep.rawValue,
            name: Localized.Integrations.Platform.Kind.sleep
        ),
        PlatformDataKind(
            use: .saves,
            key: HealthSave.bodyMeasurements.rawValue,
            name: Localized.Integrations.Platform.Kind.bodyMeasurements
        ),
    ]

    func access() async -> PlatformAccess {
        guard service.isAvailable() else { return .refused }
        guard await service.hasAsked() else { return .notAsked }
        let refused = Set(service.notAllowedSaves().map(\.rawValue))
        return .allowed(notAllowed: Set(Self.saves.filter { refused.contains($0.key) }))
    }

    func request() async -> PlatformAccess {
        _ = await service.authorize(canPromptUser: true)
        return await access()
    }
}

/// Calendar's permission. iOS can share calendars add-only, which lets Eigin
/// save events it can't see.
struct CalendarPermission: PlatformPermission {
    let service: any CalendarService

    nonisolated static let reads = [
        PlatformDataKind(
            use: .reads,
            key: "events",
            name: Localized.Integrations.Platform.Kind.events
        ),
    ]
    nonisolated static let saves = [
        PlatformDataKind(
            use: .saves,
            key: "events",
            name: Localized.Integrations.Platform.Kind.events
        ),
    ]

    func access() async -> PlatformAccess {
        switch service.access() {
        case .notAsked: .notAsked
        case .full: .allowed(notAllowed: [])
        case .addOnly: .allowed(notAllowed: Set(Self.reads))
        case .none: .refused
        }
    }

    func request() async -> PlatformAccess {
        _ = await service.authorize(canPromptUser: true)
        return await access()
    }
}

/// Reminders' permission: all or nothing.
struct RemindersPermission: PlatformPermission {
    let service: any ReminderService

    nonisolated static let reads = [
        PlatformDataKind(
            use: .reads,
            key: "reminders",
            name: Localized.Integrations.Platform.Kind.reminders
        ),
    ]
    nonisolated static let saves = [
        PlatformDataKind(
            use: .saves,
            key: "reminders",
            name: Localized.Integrations.Platform.Kind.reminders
        ),
    ]

    func access() async -> PlatformAccess {
        switch service.access() {
        case .notAsked: .notAsked
        case .full, .addOnly: .allowed(notAllowed: [])
        case .none: .refused
        }
    }

    func request() async -> PlatformAccess {
        _ = await service.authorize(canPromptUser: true)
        return await access()
    }
}

/// Location's permission, while Eigin is in use.
struct LocationPermission: PlatformPermission {
    nonisolated static let reads = [
        PlatformDataKind(
            use: .reads,
            key: "location",
            name: Localized.Integrations.Platform.Kind.location
        ),
    ]

    func access() async -> PlatformAccess {
        Self.access(LocationResolver.authorization())
    }

    func request() async -> PlatformAccess {
        await Self.access(LocationResolver.requestAuthorization())
    }

    private static func access(_ status: CLAuthorizationStatus) -> PlatformAccess {
        switch status {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse, .authorizedAlways: .allowed(notAllowed: [])
        default: .refused
        }
    }
}
