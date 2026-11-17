import SwiftUI

/// Presents one immutable permission request through its complete dismissal lifecycle.
struct PermissionSheet: ViewModifier {
    let request: PermissionRequest?
    let agentName: String
    let onResponse: (PermissionResponse, String) -> Void

    @State private var presentation = PermissionPresentation()

    func body(content: Content) -> some View {
        content
            .onChange(of: request, initial: true) { _, request in
                presentation.update(request)
            }
            .appSheet(
                isPresented: $presentation.isPresented,
                title: Localized.Permission.sheetTitle,
                descriptionContent: presentation.active.map { request in
                    AnyView(PermissionDisclosureText(
                        agentName: agentName,
                        toolDisplayName: request.toolDisplayName,
                        disclosure: request.disclosure
                    ))
                },
                fitsContent: true,
                onDismiss: {
                    if let dismissed = presentation.didDismiss() {
                        onResponse(.deny, dismissed.id)
                    }
                }
            ) {
                if let request = presentation.active {
                    PermissionRequestSheetContent(
                        agentName: agentName,
                        toolDisplayName: request.toolDisplayName,
                        disclosure: request.disclosure,
                        allowOnceLabel: Localized.Permission.allowOnce,
                        allowForChatLabel: Localized.Permission.allowForChat,
                        denyLabel: Localized.Permission.deny,
                        onResponse: { response in
                            presentation.isPresented = false
                            onResponse(response, request.id)
                        }
                    )
                    .id(request.id)
                }
            }
    }
}
