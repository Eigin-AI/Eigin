import Factory
import SwiftUI

/// A horizontal strip of thumbnails for images staged in the chat composer.
///
/// Each thumbnail shows the image with a remove button. Displayed above the
/// input bar when ``ChatViewModel/stagedAttachments`` is non-empty.
struct StagedAttachmentsView: View {
    let attachments: [MessageAttachment]
    let onRemove: (MessageAttachment) -> Void

    @Environment(\.colors) private var colors
    @Injected(\.chatAttachmentStore) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                ForEach(attachments) { attachment in
                    ThumbnailView(attachment: attachment, store: store) {
                        onRemove(attachment)
                    }
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.vertical, Spacing.n8)
        }
    }
}

// MARK: - Thumbnail

private struct ThumbnailView: View {
    let attachment: MessageAttachment
    let store: any ChatAttachmentStoring
    let onRemove: () -> Void

    @Environment(\.colors) private var colors
    @State private var image: UIImage?

    private let size: CGFloat = 72

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    colors.surface.standard.elevated
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card / 2, style: .continuous))

            AppActionButton(
                icon: Iconography.Functional.x,
                variant: .open,
                size: .extraSmall,
                action: onRemove
            )
            .accessibilityLabel(Localized.Attachment.removeImage)
        }
        .task(id: attachment.id) {
            if let data = store.loadThumbnail(id: attachment.id) {
                image = UIImage(data: data)
            }
        }
    }
}
