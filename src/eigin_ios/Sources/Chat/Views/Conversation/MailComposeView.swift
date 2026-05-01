import MessageUI
import SwiftUI

struct MailComposeView: UIViewControllerRepresentable {
    let request: ComposeEmailRequest
    let continuation: CheckedContinuation<ComposeEmailResult, Never>

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(request.to)
        if !request.cc.isEmpty { vc.setCcRecipients(request.cc) }
        if !request.bcc.isEmpty { vc.setBccRecipients(request.bcc) }
        if !request.subject.isEmpty { vc.setSubject(request.subject) }
        if !request.body.isEmpty { vc.setMessageBody(request.body, isHTML: request.isHTML) }
        return vc
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(continuation: continuation)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        nonisolated(unsafe) var continuation: CheckedContinuation<ComposeEmailResult, Never>?

        init(continuation: CheckedContinuation<ComposeEmailResult, Never>) {
            self.continuation = continuation
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            let mapped: ComposeEmailResult = switch result {
            case .sent: .sent
            case .cancelled: .cancelled
            case .saved: .saved
            case .failed: .failed
            @unknown default: .failed
            }

            let cont = continuation
            continuation = nil
            cont?.resume(returning: mapped)
            Task { @MainActor in
                controller.dismiss(animated: true)
            }
        }
    }
}
