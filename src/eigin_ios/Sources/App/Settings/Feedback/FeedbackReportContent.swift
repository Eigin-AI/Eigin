import MessageUI
import SwiftUI

private struct MailSession: Identifiable {
    let id = UUID()
    let continuation: CheckedContinuation<MFMailComposeResult, Never>
}

struct FeedbackReportContent: View {
    let report: FeedbackReport

    @Environment(\.colors) private var colors
    @State private var mailSession: MailSession?

    var body: some View {
        VStack(spacing: contentGap) {
            reportCard
            actionButtons
        }
        .sheet(item: $mailSession) { session in
            FeedbackMailComposeView(report: report, continuation: session.continuation)
        }
    }

    // MARK: - Subviews

    private var reportCard: some View {
        ScrollView {
            Text(report.body)
                .typography(Typography.note)
                .foregroundStyle(colors.text.standard.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.n16)
        }
        .frame(maxHeight: 280)
        .background(colors.surface.standard.alternative)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, contentPx)
    }

    private var actionButtons: some View {
        HStack(spacing: Spacing.n12) {
            Spacer()
            AppButton(Localized.Settings.Feedback.copyButton, variant: .secondary, size: .medium) {
                UIPasteboard.general.string = report.body
            }
            if MFMailComposeViewController.canSendMail() {
                AppButton(Localized.Settings.Feedback.sendButton, size: .medium) {
                    Task {
                        _ = await withCheckedContinuation { (cont: CheckedContinuation<
                            MFMailComposeResult,
                            Never
                        >) in
                            mailSession = MailSession(continuation: cont)
                        }
                        mailSession = nil
                    }
                }
            }
        }
        .padding(.horizontal, contentPx)
    }
}

// MARK: - Mail Compose

private struct FeedbackMailComposeView: UIViewControllerRepresentable {
    let report: FeedbackReport
    let continuation: CheckedContinuation<MFMailComposeResult, Never>

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([AppKeys.supportEmail])
        vc.setSubject(report.subject)
        vc.setMessageBody(report.body, isHTML: false)
        if let data = report.logData {
            vc.addAttachmentData(data, mimeType: "text/plain", fileName: "eigin.log")
        }
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
        nonisolated(unsafe) var continuation: CheckedContinuation<MFMailComposeResult, Never>?

        init(continuation: CheckedContinuation<MFMailComposeResult, Never>) {
            self.continuation = continuation
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            let cont = continuation
            continuation = nil
            cont?.resume(returning: result)
            Task { @MainActor in
                controller.dismiss(animated: true)
            }
        }
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

// MARK: - Preview

#Preview {
    let report = FeedbackReport(
        type: .bug,
        description: "When I tap the microphone button twice in quick succession the app crashes.",
        includeLogs: false
    )
    Color.clear
        .appSheet(isPresented: .constant(true), title: "Review & Send", detents: [.large]) {
            FeedbackReportContent(report: report)
        }
        .previewEnvironment()
}
