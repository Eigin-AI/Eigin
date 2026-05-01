@testable import Eigin
import Foundation
import Testing

@Suite("SystemHintBuilder")
@MainActor
struct SystemHintBuilderTests {
    // MARK: - Helpers

    private func input() -> SystemHintInput {
        SystemHintInput(
            agentID: UUID(),
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: [],
            space: nil,
            spaceID: nil,
            language: nil,
            mode: .text,
            activeIntents: [],
            activeSkills: [],
            availableSkills: [],
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: false
        )
    }

    // MARK: - Tests

    @Test func buildWrapsSectionsInSystemHintTag() async {
        let sources: [any SystemHintSource] = [
            StubSource(title: "One", body: "first body"),
            StubSource(title: "Two", body: "second body"),
        ]
        let output = await SystemHintBuilder.build(sources: sources, input: input())
        #expect(output != nil)
        let text = output ?? ""
        #expect(text.hasPrefix("<system_hint>\n"))
        #expect(text.hasSuffix("\n</system_hint>"))
        #expect(text.contains("## One\n\nfirst body"))
        #expect(text.contains("## Two\n\nsecond body"))
        // Sections should be separated by a blank line.
        #expect(text.contains("first body\n\n## Two"))
    }

    @Test func buildSkipsNilSources() async {
        let sources: [any SystemHintSource] = [
            StubSource(title: "Present", body: "body"),
            StubSource(title: "Absent", body: nil),
            StubSource(title: "AlsoPresent", body: "more"),
        ]
        let output = await SystemHintBuilder.build(sources: sources, input: input()) ?? ""
        #expect(output.contains("## Present"))
        #expect(output.contains("## AlsoPresent"))
        #expect(!output.contains("## Absent"))
    }

    @Test func buildReturnsNilWhenAllSourcesSilent() async {
        let sources: [any SystemHintSource] = [
            StubSource(title: "A", body: nil),
            StubSource(title: "B", body: nil),
        ]
        let output = await SystemHintBuilder.build(sources: sources, input: input())
        #expect(output == nil)
    }

    @Test func buildTreatsEmptyBodyAsNil() async {
        let sources: [any SystemHintSource] = [
            StubSource(title: "Empty", body: ""),
            StubSource(title: "Real", body: "body"),
        ]
        let output = await SystemHintBuilder.build(sources: sources, input: input()) ?? ""
        #expect(!output.contains("## Empty"))
        #expect(output.contains("## Real"))
    }

    @Test func buildReturnsNilForEmptySourceList() async {
        let output = await SystemHintBuilder.build(sources: [], input: input())
        #expect(output == nil)
    }

    @Test func buildPreservesSourceOrder() async throws {
        let sources: [any SystemHintSource] = [
            StubSource(title: "Zebra", body: "z"),
            StubSource(title: "Alpha", body: "a"),
            StubSource(title: "Mike", body: "m"),
        ]
        let output = await SystemHintBuilder.build(sources: sources, input: input()) ?? ""
        let zebraRange = try #require(output.range(of: "## Zebra"))
        let alphaRange = try #require(output.range(of: "## Alpha"))
        let mikeRange = try #require(output.range(of: "## Mike"))
        #expect(zebraRange.lowerBound < alphaRange.lowerBound)
        #expect(alphaRange.lowerBound < mikeRange.lowerBound)
    }
}

// MARK: - Stub source

@MainActor
private final class StubSource: SystemHintSource {
    let title: String
    let body: String?
    init(title: String, body: String?) {
        self.title = title
        self.body = body
    }

    func render(_ input: SystemHintInput) async -> String? {
        body
    }
}
