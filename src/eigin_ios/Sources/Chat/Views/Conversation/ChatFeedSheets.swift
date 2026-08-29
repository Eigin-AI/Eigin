import PhotosUI
import SwiftUI
import UIKit

/// Presentation state for the sheets a ``ChatFeed`` can host. Grouped so the feed
/// carries one observable object instead of a flag per modal.
@Observable @MainActor
final class ChatFeedSheetState {
    var selectedError: ConnectionError?
    var permissionRequest: PermissionRequest?
    var browsingRequest: BrowsingRequest?
    var browsingPageReady = false
    var showActionSheet = false
    var showSpacePicker = false
    var showPhotoPicker = false
    var showCamera = false
    var selectedPhotoItems: [PhotosPickerItem] = []
}

/// Hosts every sheet, picker, and cover a ``ChatFeed`` presents, keyed off
/// ``ChatFeedSheetState``. Keeps sheet routing out of the feed's body so a change
/// to one modal can't disturb scroll or input layout.
struct ChatFeedSheets: ViewModifier {
    @Bindable var state: ChatFeedSheetState
    let context: FeedContext
    let interactions: FeedInteractions

    func body(content: Content) -> some View {
        content
            // Mirror incoming interaction requests into local presentation state.
            .onChange(of: interactions.permissionRequest) { _, new in
                if let new { state.permissionRequest = new }
            }
            .onChange(of: interactions.browsingRequest) { _, new in
                if let new {
                    state.browsingRequest = new
                    state.browsingPageReady = false
                }
            }
            .appSheet(
                isPresented: Binding(
                    get: { state.selectedError != nil },
                    set: { if !$0 { state.selectedError = nil } }
                ),
                title: state.selectedError?.title ?? "Error",
                description: state.selectedError?.suggestion,
                detents: [.medium, .large]
            ) {
                if let error = state.selectedError {
                    ErrorDetailSheet(error: error)
                }
            }
            .appSheet(
                isPresented: Binding(
                    get: { state.permissionRequest != nil },
                    set: { if !$0 { state.permissionRequest = nil } }
                ),
                title: Localized.Permission.sheetTitle,
                descriptionContent: state.permissionRequest.map { request in
                    AnyView(PermissionDisclosureText(
                        agentName: context.agentName,
                        toolDisplayName: request.toolDisplayName,
                        disclosure: request.disclosure
                    ))
                },
                fitsContent: true
            ) {
                if let request = state.permissionRequest {
                    PermissionRequestSheetContent(
                        agentName: context.agentName,
                        toolDisplayName: request.toolDisplayName,
                        disclosure: request.disclosure,
                        allowOnceLabel: Localized.Permission.allowOnce,
                        allowForChatLabel: Localized.Permission.allowForChat,
                        denyLabel: Localized.Permission.deny,
                        onResponse: { response in
                            interactions.onPermissionResponse?(response)
                        }
                    )
                }
            }
            .appSheet(
                isPresented: Binding(
                    get: { state.browsingRequest != nil },
                    set: { if !$0 { state.browsingRequest = nil } }
                ),
                title: Localized.Browsing.title,
                description: state.browsingPageReady
                    ? Localized.Agent.Status.readingPage(actorName)
                    : Localized.Agent.Status.loadingPage(actorName),
                detents: [.medium],
                showsDismissButton: false,
                onDismiss: {
                    dismissBrowsing(
                        result: .error("User dismissed the browser before request completed.")
                    )
                }
            ) {
                WebBrowsingSheetContent(
                    request: state.browsingRequest!,
                    onComplete: dismissBrowsing,
                    onPageReadyChanged: { ready in state.browsingPageReady = ready }
                )
            }
            .appSheet(
                isPresented: $state.showActionSheet,
                title: Localized.Actions.title,
                detents: [.medium],
                fitsContent: true
            ) {
                ActionSheetContent(actions: actionSheetItems)
            }
            .photosPicker(
                isPresented: $state.showPhotoPicker,
                selection: $state.selectedPhotoItems,
                maxSelectionCount: 1,
                matching: .images
            )
            .onChange(of: state.selectedPhotoItems) { _, items in
                guard let item = items.first else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)
                    {
                        context.onStageImage?(image)
                    }
                    state.selectedPhotoItems = []
                }
            }
            .fullScreenCover(isPresented: $state.showCamera) {
                CameraPickerView(
                    onCapture: { image in
                        state.showCamera = false
                        context.onStageImage?(image)
                    },
                    onCancel: { state.showCamera = false }
                )
                .ignoresSafeArea()
            }
            .appSheet(
                isPresented: $state.showSpacePicker,
                title: Localized.Debug.moveToSpaceTitle,
                detents: [.medium, .large],
                fitsContent: true
            ) {
                SpacePickerSheetContent(
                    spaces: context.spaces,
                    currentSpaceID: context.currentSpaceID,
                    onSelect: { spaceID in context.onMoveToSpace?(spaceID) }
                )
            } secondary: {
                if context.currentSpaceID != nil {
                    AppButton(
                        Localized.Space.removeFromSpace,
                        variant: .destructive
                    ) {
                        context.onMoveToSpace?(nil)
                    }
                    .padding(.horizontal, Sizing.PageLayout.ContentGrouping.Px.mobile)
                }
            }
    }

    private var actorName: String {
        context.agentName.isEmpty || context.agentName.count > 20 ? "Agent" : context.agentName
    }

    /// Action-sheet items for the input's action button, based on available capabilities.
    private var actionSheetItems: [ActionItem] {
        var items: [ActionItem] = []

        if context.supportsVision,
           context.stagedAttachments.count < ChatViewModel.maxStagedAttachments
        {
            items.append(ActionItem(
                label: Localized.Attachment.takePhoto,
                icon: Image(systemName: "camera"),
                action: {
                    state.showActionSheet = false
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        state.showCamera = true
                    }
                }
            ))
            items.append(ActionItem(
                label: Localized.Attachment.attachImage,
                icon: Image(systemName: "photo"),
                action: {
                    state.showActionSheet = false
                    state.showPhotoPicker = true
                }
            ))
        }

        if context.onMoveToSpace != nil, !context.spaces.isEmpty {
            items.append(ActionItem(
                label: Localized.Debug.moveToSpaceTitle,
                icon: Iconography.Brand.security,
                action: {
                    state.showActionSheet = false
                    state.showSpacePicker = true
                }
            ))
        }

        return items
    }

    private func dismissBrowsing(result: BrowsingResult) {
        state.browsingRequest = nil
        interactions.onBrowsingComplete?(result)
    }
}
