@testable import Eigin
import Testing

@Suite("Permission presentation")
@MainActor
struct PermissionPresentationTests {
    private let a = PermissionRequest(
        id: "a",
        toolName: "read_core",
        toolDisplayName: "Read",
        disclosure: nil
    )
    private let b = PermissionRequest(
        id: "b",
        toolName: "read_core",
        toolDisplayName: "Read",
        disclosure: nil
    )

    @Test func nextRequestWaitsForDismissal() {
        let presentation = PermissionPresentation()
        presentation.update(a)
        presentation.isPresented = false
        presentation.update(nil)
        presentation.update(b)
        #expect(presentation.active == a)
        #expect(!presentation.isPresented)
        #expect(presentation.didDismiss() == a)
        #expect(presentation.active == b)
        #expect(presentation.isPresented)
    }

    @Test func swipeReturnsOnlyTheDisplayedRequest() {
        let presentation = PermissionPresentation()
        presentation.update(a)
        presentation.isPresented = false
        #expect(presentation.didDismiss() == a)
        #expect(presentation.active == nil)
        #expect(!presentation.isPresented)
        presentation.update(b)
        #expect(presentation.active == b)
        #expect(presentation.isPresented)
    }

    @Test func stopDiscardsTheNextRequest() {
        let presentation = PermissionPresentation()
        presentation.update(a)
        presentation.update(b)
        presentation.update(nil)
        #expect(presentation.didDismiss() == a)
        #expect(presentation.active == nil)
        #expect(!presentation.isPresented)
    }
}
