import Factory
import Foundation

/// Integrations iOS gives permission for, rather than an account.
///
/// Their tools never prompt iOS themselves: connecting is where iOS asks, after
/// the person has seen what Eigin will read and save.
extension BundledIntegrationType {
    static let platform: [IntegrationType] = [appleHealth, appleCalendar, appleReminders, location]

    static let appleHealth = IntegrationType(
        id: "apple-health",
        displayName: Localized.Integrations.Platform.AppleHealth.displayName,
        description: Localized.Integrations.Platform.AppleHealth.description,
        systemImage: "heart.fill",
        brandImage: Iconography.Functional.heart,
        providedCapabilities: [.health],
        category: .platform,
        authKind: .platform(PlatformAccessSource(
            reads: HealthPermission.reads,
            saves: HealthPermission.saves,
            asker: Localized.Integrations.Platform.Place.health,
            permission: { HealthPermission(service: Container.shared.healthService()) }
        )),
        toolCapabilities: HealthToolKit.capabilities,
        makeTools: { capability, _, context in
            guard capability == .health else { return [] }
            return HealthToolKit.tools(context: context.withoutPrompting)
        }
    )

    static let appleCalendar = IntegrationType(
        id: "apple-calendar",
        displayName: Localized.Integrations.Platform.AppleCalendar.displayName,
        description: Localized.Integrations.Platform.AppleCalendar.description,
        systemImage: "calendar",
        brandImage: Iconography.Brand.calendar,
        providedCapabilities: [.calendar],
        category: .platform,
        authKind: .platform(PlatformAccessSource(
            reads: CalendarPermission.reads,
            saves: CalendarPermission.saves,
            asker: "iOS",
            permission: { CalendarPermission(service: Container.shared.calendarService()) }
        )),
        toolCapabilities: CalendarToolKit.capabilities,
        makeTools: { capability, _, context in
            guard capability == .calendar else { return [] }
            return CalendarToolKit.tools(context: context.withoutPrompting)
        }
    )

    static let appleReminders = IntegrationType(
        id: "apple-reminders",
        displayName: Localized.Integrations.Platform.AppleReminders.displayName,
        description: Localized.Integrations.Platform.AppleReminders.description,
        systemImage: "checklist",
        brandImage: Iconography.Functional.checkCircle,
        providedCapabilities: [.reminders],
        category: .platform,
        authKind: .platform(PlatformAccessSource(
            reads: RemindersPermission.reads,
            saves: RemindersPermission.saves,
            asker: "iOS",
            permission: { RemindersPermission(service: Container.shared.reminderService()) }
        )),
        toolCapabilities: ReminderToolKit.capabilities,
        makeTools: { capability, _, context in
            guard capability == .reminders else { return [] }
            return ReminderToolKit.tools(context: context.withoutPrompting)
        }
    )

    /// Has no tools of its own: the awareness tools use location when it is
    /// connected and allowed, and work without it otherwise.
    static let location = IntegrationType(
        id: "location",
        displayName: Localized.Integrations.Platform.Location.displayName,
        description: Localized.Integrations.Platform.Location.description,
        systemImage: "location.fill",
        brandImage: Iconography.Functional.location,
        providedCapabilities: [.location],
        category: .platform,
        authKind: .platform(PlatformAccessSource(
            reads: LocationPermission.reads,
            saves: [],
            asker: "iOS",
            permission: { LocationPermission() }
        )),
        toolCapabilities: [],
        makeTools: { _, _, _ in [] }
    )
}

private extension ToolContext {
    /// The same context with prompting turned off.
    var withoutPrompting: ToolContext {
        var context = self
        context.canPromptUser = false
        return context
    }
}
