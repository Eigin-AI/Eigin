import SwiftUI

/// Shows a single progress line filling left-to-right during compaction, with the label
/// overlaid on top (masking the line behind it). Switches to "Conversation summarized" when done.
/// When a summary is available, tapping the divider expands to show the summary text.
struct CompactionDivider: View {
    let progress: Float? // nil = finished, 0–1 = in-progress
    var summary: String?

    @Environment(\.colors) private var colors
    @State private var isExpanded = false

    private var isCompacting: Bool {
        progress != nil
    }

    private var hasSummary: Bool {
        summary != nil && !isCompacting
    }

    var body: some View {
        VStack(spacing: 0) {
            dividerLine

            if isExpanded, let summary {
                let cleaned = summary.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.replacingOccurrences(
                        of: "^#{1,6}\\s*",
                        with: "",
                        options: .regularExpression
                    ) }
                    .joined(separator: "\n")
                let rendered = (try? AttributedString(
                    markdown: cleaned,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ))
                    ?? AttributedString(cleaned)
                Text(rendered)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.n8)
                    .padding(.horizontal, Spacing.n8)
            }
        }
        .padding(.vertical, Spacing.n4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasSummary else { return }
            withAnimation(Animations.smooth) {
                isExpanded.toggle()
            }
        }
    }

    private var dividerLine: some View {
        ZStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(colors.border.standard.base)
                        .frame(height: 1)

                    if let progress {
                        Rectangle()
                            .fill(colors.accent)
                            .frame(
                                width: geo.size.width * CGFloat(min(max(progress, 0), 1)),
                                height: 2
                            )
                            .animation(Animations.smooth, value: progress)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 2)

            HStack(spacing: Spacing.n4) {
                Text(isCompacting ? "Compacting…" : "Conversation summarized")
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)

                if hasSummary {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
            .padding(.horizontal, Spacing.n8)
            .background(colors.surface.standard.base)
        }
    }
}
