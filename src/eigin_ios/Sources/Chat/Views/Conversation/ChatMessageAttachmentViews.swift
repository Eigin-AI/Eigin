import Factory
import QuickLook
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

// MARK: - Attachment preview (QuickLook)

/// Wraps `QLPreviewController` to show a message's image attachments as a
/// swipeable gallery, starting at `initialIndex`. Titles use a friendly
/// placeholder (rather than the on-disk UUID filename) and Markup editing
/// is disabled.
private struct AttachmentPreview: UIViewControllerRepresentable {
    let attachments: [MessageAttachment]
    let store: any ChatAttachmentStoring
    let initialIndex: Int
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismiss)
        )
        if context.coordinator.items.indices.contains(initialIndex) {
            controller.currentPreviewItemIndex = initialIndex
        }
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(attachments: attachments, store: store, isPresented: $isPresented)
    }

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource,
        @preconcurrency QLPreviewControllerDelegate
    {
        let items: [AttachmentPreviewItem]
        private let isPresented: Binding<Bool>

        init(
            attachments: [MessageAttachment],
            store: any ChatAttachmentStoring,
            isPresented: Binding<Bool>
        ) {
            items = attachments.compactMap { attachment in
                store.fileURL(for: attachment.id).map(AttachmentPreviewItem.init)
            }
            self.isPresented = isPresented
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            items.count
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            items[index]
        }

        func previewController(
            _ controller: QLPreviewController,
            editingModeFor previewItem: QLPreviewItem
        ) -> QLPreviewItemEditingMode {
            .disabled
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            isPresented.wrappedValue = false
        }

        @objc func dismiss() {
            isPresented.wrappedValue = false
        }
    }
}

/// `QLPreviewItem` with a fixed, friendly title in place of the attachment's
/// on-disk UUID filename.
private final class AttachmentPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL) {
        previewItemURL = url
        previewItemTitle = Localized.Attachment.previewTitle
    }
}
