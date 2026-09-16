import SwiftUI
import WidgetKit

/// Watch face complication and Smart Stack widget that opens Eigin. A
/// complication cannot hold a press, so it is only ever a launcher — the
/// question starts when the wearer pushes and holds on the blob.
struct AskComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AskComplication", provider: AskProvider()) { _ in
            AskComplicationView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(Localized.Watch.askEigin)
        .description(Localized.Watch.complicationDescription)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

/// The complication is a launch button, so it has nothing to schedule.
struct AskProvider: TimelineProvider {
    func placeholder(in context: Context) -> AskEntry {
        AskEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (AskEntry) -> Void) {
        completion(AskEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AskEntry>) -> Void) {
        completion(Timeline(entries: [AskEntry(date: .now)], policy: .never))
    }
}

struct AskEntry: TimelineEntry {
    let date: Date
}

struct AskComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(Localized.Watch.askEigin, systemImage: "mic.fill")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                mark
                    .frame(height: 20)
                Text(Localized.Watch.askEigin)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            mark
        }
    }

    /// The E mark as an alpha glyph — the face tints it along with every
    /// other complication. Full-color artwork is not possible: accented
    /// faces flatten opaque images to a single tint, keeping only alpha.
    private var mark: some View {
        Image("complication_mark")
            .resizable()
            .scaledToFit()
    }
}

@main
struct EiginWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        AskComplication()
    }
}
