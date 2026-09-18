import QuickLook
import SwiftUI

// MARK: - Attachment preview (QuickLook)

/// Shows images full screen in a swipeable gallery, wrapped `QLPreviewController`:
/// an image per attachment, or one file titled with arbitrary text. Markup
/// editing is disabled.
struct AttachmentPreview: UIViewControllerRepresentable {
    private let items: [PreviewItem]
    private let initialIndex: Int
    @Binding private var isPresented: Bool

    init(
        attachments: [MessageAttachment],
        store: any ChatAttachmentStoring,
        initialIndex: Int = 0,
        isPresented: Binding<Bool>
    ) {
        items = attachments.compactMap { attachment in
            store.fileURL(for: attachment.id).map { PreviewItem(url: $0) }
        }
        self.initialIndex = initialIndex
        _isPresented = isPresented
    }

    /// A single file presented on its own, titled with arbitrary text (for a
    /// chat image card, its alt text).
    init(url: URL, title: String?, isPresented: Binding<Bool>) {
        items = [PreviewItem(url: url, title: title)]
        initialIndex = 0
        _isPresented = isPresented
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismiss)
        )
        if items.indices.contains(initialIndex) {
            controller.currentPreviewItemIndex = initialIndex
        }
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, isPresented: $isPresented)
    }

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource,
        @preconcurrency QLPreviewControllerDelegate
    {
        private let items: [PreviewItem]
        private let isPresented: Binding<Bool>

        init(items: [PreviewItem], isPresented: Binding<Bool>) {
            self.items = items
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

/// `QLPreviewItem` with a friendly title in place of an on-disk UUID filename.
final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    /// No explicit title keeps the folder-style name of user attachments the
    /// flow already assumed; `Localized.Attachment.previewTitle` for the gallery.
    init(url: URL, title: String? = Localized.Attachment.previewTitle) {
        previewItemURL = url
        previewItemTitle = title
    }
}
