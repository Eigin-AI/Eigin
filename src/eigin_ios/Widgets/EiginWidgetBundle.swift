import SwiftUI
import WidgetKit

/// The Eigin widget family: quick actions that open straight into a chat.
@main
struct EiginWidgetBundle: WidgetBundle {
    /// Bundled fonts are registered with `.process` scope, so the extension has
    /// to register its own copy — the app doing it at launch does not carry
    /// over into this process.
    init() {
        FontRegistration.register()
    }

    var body: some Widget {
        QuickActionsWidget()
    }
}

/// A timeline provider for buttons that never change — the widget reads no app
/// data, so a single static entry is all it needs.
struct StaticSnapshot: TimelineEntry, Hashable {
    let date = Date.distantFuture
}

struct ActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticSnapshot {
        StaticSnapshot()
    }

    func getSnapshot(in context: Context, completion: @escaping (StaticSnapshot) -> Void) {
        completion(StaticSnapshot())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<StaticSnapshot>) -> Void
    ) {
        completion(Timeline(entries: [StaticSnapshot()], policy: .never))
    }
}

/// Buttons for the three chat actions plus the brand avatar, which just opens
/// the app.
struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EiginQuickActions", provider: ActionsProvider()) { _ in
            QuickActionsView()
        }
        .configurationDisplayName(String(localized: "widgets.name"))
        .description(String(localized: "widgets.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
