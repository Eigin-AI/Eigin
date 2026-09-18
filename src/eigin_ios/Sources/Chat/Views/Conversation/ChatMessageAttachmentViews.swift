import Factory
import SwiftUI
import UIKit

// MARK: - Attached images (user messages)

/// Row of image thumbnails for a sent user message. Lays out inline when the
/// attachments fit the available width, and falls back to a horizontal
/// scroll view only when they don't.
struct AttachedImagesView: View {
    let attachments: [MessageAttachment]

    @Injected(\.chatAttachmentStore) private var store
    @State private var previewIndex: Int?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            thumbnailRow
            ScrollView(.horizontal, showsIndicators: false) {
                thumbnailRow
            }
        }
        .fullScreenCover(isPresented: isShowingPreview) {
            AttachmentPreview(
                attachments: attachments,
                store: store,
                initialIndex: previewIndex ?? 0,
                isPresented: isShowingPreview
            )
            .ignoresSafeArea()
        }
    }

    private var isShowingPreview: Binding<Bool> {
        Binding(
            get: { previewIndex != nil },
            set: { if !$0 { previewIndex = nil } }
        )
    }

    private var thumbnailRow: some View {
        HStack(spacing: Spacing.n8) {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                AttachedImageThumbnail(attachment: attachment, store: store) {
                    previewIndex = index
                }
            }
        }
    }
}

private struct AttachedImageThumbnail: View {
    let attachment: MessageAttachment
    let store: any ChatAttachmentStoring
    let onTap: () -> Void

    @State private var image: UIImage?

    private let size: CGFloat = Spacing.n88

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card / 2, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .task(id: attachment.id) {
            if let data = store.loadThumbnail(id: attachment.id) {
                image = UIImage(data: data)
            }
        }
    }
}
