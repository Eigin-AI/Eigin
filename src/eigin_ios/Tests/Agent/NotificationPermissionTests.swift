@testable import Eigin
import Testing

@Suite("Notification authorization")
struct NotificationPermissionTests {
    @Test("Only interactive undetermined authorization prompts", arguments: [true, false])
    func undetermined(canPrompt: Bool) async {
        let authorization = FakeNotificationAuthorization(status: .notDetermined)
        let allowed = await NotificationPermission.requestIfNeeded(
            canPromptUser: canPrompt,
            authorization: authorization
        )
        #expect(allowed == canPrompt)
        #expect(await authorization.requestCount == (canPrompt ? 1 : 0))
    }

    @Test("Existing authorization never prompts", arguments: [true, false])
    func existing(canPrompt: Bool) async {
        let denied = FakeNotificationAuthorization(status: .denied)
        #expect(await !NotificationPermission.requestIfNeeded(
            canPromptUser: canPrompt,
            authorization: denied
        ))
        #expect(await denied.requestCount == 0)
        let allowed = FakeNotificationAuthorization(status: .authorized)
        #expect(await NotificationPermission.requestIfNeeded(
            canPromptUser: canPrompt,
            authorization: allowed
        ))
        #expect(await allowed.requestCount == 0)
        let provisional = FakeNotificationAuthorization(status: .provisional)
        #expect(await NotificationPermission.requestIfNeeded(
            canPromptUser: canPrompt,
            authorization: provisional
        ))
        #expect(await provisional.requestCount == 0)
    }
}
