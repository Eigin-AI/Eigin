@testable import Eigin
import Testing

struct MorphTimelineTests {
    @Test func entryScalesInThenSettles() {
        let timeline = MorphTimeline()
        #expect(timeline.entryScale(at: 0) == 0)
        #expect(timeline.entryScale(at: MorphTimeline.entryDuration) == 1)
        #expect(timeline.entryScale(at: 5) == 1)
        // Overshoot curve rises above 1 before settling.
        let midpoint = timeline.entryScale(at: MorphTimeline.entryDuration * 0.6)
        #expect(midpoint > 1)
    }

    @Test func startsAsCircle() {
        let timeline = MorphTimeline()
        let pose = timeline.pose(at: 0)
        #expect(pose.from == 0)
        #expect(pose.to == 0)
        #expect(pose.progress == 0)
    }

    @Test func sameSeedSameChoreography() {
        let a = MorphTimeline(seed: 42).pose(at: 17.3)
        let b = MorphTimeline(seed: 42).pose(at: 17.3)
        #expect(a == b)
    }

    @Test func differentSeedLikelyDifferentPose() {
        // Not a guarantee per seed, but across several seeds the poses differ.
        let baseline = MorphTimeline(seed: 1).pose(at: 17.3)
        let anyDifference = (2 ... 12).contains { seed in
            MorphTimeline(seed: UInt64(seed)).pose(at: 17.3) != baseline
        }
        #expect(anyDifference)
    }

    @Test func loopVisitsEveryFormOnce() {
        let timeline = MorphTimeline(seed: 11)
        let count = MorphForm.all.count
        // The seeded loop starts and ends on the circle, visiting each form
        // exactly once in between.
        #expect(timeline.sequence.first == 0)
        #expect(timeline.sequence.last == 0)
        let interior = timeline.sequence.dropFirst().dropLast()
        #expect(interior.count == count - 1)
        #expect(Set(interior).count == count - 1)
    }

    @Test func consecutiveFormsNeverRepeat() {
        let timeline = MorphTimeline(seed: 7)
        // Past the initial hold the figure is always morphing between
        // distinct forms, including across the loop seam.
        for t in stride(
            from: MorphTimeline.initialHold + 0.01,
            to: 120,
            by: 0.05
        ) {
            let pose = timeline.pose(at: t)
            #expect(pose.from != pose.to, "pose repeats a form at t=\(t)")
        }
    }

    @Test func travelStaysInRhythmBounds() throws {
        let travels = MorphTimeline.Rhythm.allCases.map(\.travel)
        let bounds = try #require(travels.map(\.lowerBound).min()) ... travels.map(\.upperBound)
            .max()!
        for segment in MorphTimeline(seed: 9).segments {
            #expect(bounds.contains(segment.travel))
        }
    }

    @Test func breathStaysSubtle() {
        // Phase is offset by π/2 (prototype parity), so the breath starts at
        // its maximum — invisible anyway, since entry scale is 0 at that moment.
        let timeline = MorphTimeline()
        #expect(timeline.breath(at: 0) == 1 + MorphTimeline.breathScaleAmplitude)
        for t in stride(from: 0.0, to: 60, by: 0.1) {
            let breath = timeline.breath(at: t)
            #expect(abs(breath - 1) <= MorphTimeline.breathScaleAmplitude + 0.0001)
        }
    }
}

struct ThinkingCopyTests {
    @Test func silentBeforeFirstThreshold() {
        #expect(ThinkingCopy.stage(at: 0) == nil)
        #expect(ThinkingCopy.stage(at: 4.4) == nil)
    }

    @Test func stagesArriveInOrder() {
        let ladder: [(TimeInterval, ThinkingCopy)] = [
            (4.5, .thinking),
            (11, .stillThinking),
            (18, .almostThere),
            (29, .takingAWhile),
            (44, .sorryForTheWait),
        ]
        for (t, stage) in ladder {
            #expect(ThinkingCopy.stage(at: t) == stage)
            #expect(ThinkingCopy.stage(at: t + 0.1) == stage)
        }
    }

    @Test func staysOnLastRung() {
        #expect(ThinkingCopy.stage(at: 300) == .sorryForTheWait)
    }

    @Test func boundaryTransitions() {
        #expect(ThinkingCopy.stage(at: ThinkingCopy.thresholds[1] - 0.01) == .thinking)
        #expect(ThinkingCopy.stage(at: ThinkingCopy.thresholds[1]) == .stillThinking)
    }
}
