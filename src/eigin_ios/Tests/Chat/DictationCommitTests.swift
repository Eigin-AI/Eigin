@testable import Eigin
import Testing

@MainActor
@Suite("DictationCommit")
struct DictationCommitTests {
    // MARK: - combining

    @Test("combining keeps pre-dictation text untouched when dictation is empty")
    func combiningEmptyDictation() {
        #expect(DictationCommit.combining("hello", "") == "hello")
    }

    @Test("combining appends dictation after pre-dictation text")
    func combiningBoth() {
        #expect(DictationCommit.combining("hello", "world") == "hello world")
    }

    @Test("combining trims surrounding whitespace from the dictation result")
    func combiningTrimsDictation() {
        #expect(DictationCommit.combining("hello", " world ") == "hello world")
        #expect(DictationCommit.combining("hello", "  ") == "hello")
    }

    @Test("combining uses dictation alone when there is no pre-dictation text")
    func combiningEmptyBefore() {
        #expect(DictationCommit.combining("", "world") == "world")
    }

    @Test("combining with nothing on either side is empty")
    func combiningBothEmpty() {
        #expect(DictationCommit.combining("", "") == "")
    }

    // MARK: - commit

    @Test("commit returns the finalized text combined with pre-dictation text")
    func commitCombinesFinalizedText() async {
        let fake = FakeDictationService()
        fake.finishDelay = .milliseconds(50)
        fake.finishResult = "world"
        let commit = DictationCommit(dictation: fake)

        let text = await commit.commit(before: "hello")

        #expect(text == "hello world")
        #expect(fake.finishCallCount == 1)
        #expect(!commit.isFinishing)
    }

    @Test("commit rejects re-entry while a finalization is in flight")
    func commitRejectsConcurrentCommits() async {
        let fake = FakeDictationService()
        fake.finishDelay = .milliseconds(80)
        fake.finishResult = "world"
        let commit = DictationCommit(dictation: fake)

        let first = Task { await commit.commit(before: "hello") }
        // Give the first commit time to enter its finalize window.
        try? await Task.sleep(for: .milliseconds(20))

        let second = await commit.commit(before: "hello")
        #expect(second == nil)
        #expect(commit.isFinishing)

        let finalized = await first.value
        #expect(finalized == "hello world")
        #expect(fake.finishCallCount == 1)
        #expect(!commit.isFinishing)
    }
}
