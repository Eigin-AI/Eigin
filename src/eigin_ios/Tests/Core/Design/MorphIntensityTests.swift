@testable import Eigin
import Testing

struct MorphIntensityTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func engagedRampsFromZeroToOne() {
        let intensity = MorphIntensity(engaged: true, changedAt: start)
        #expect(intensity.value(at: start) == 0)
        #expect(intensity.value(at: start.addingTimeInterval(Animations.slow)) == 1)
        // Monotone in between, already rising immediately after the change.
        #expect(intensity.value(at: start.addingTimeInterval(Animations.slow * 0.25)) > 0)
        #expect(
            intensity.value(at: start.addingTimeInterval(Animations.slow * 0.25))
                < intensity.value(at: start.addingTimeInterval(Animations.slow * 0.75))
        )
    }

    @Test func disengagedRampsFromOneToZero() {
        let intensity = MorphIntensity(engaged: false, changedAt: start)
        #expect(intensity.value(at: start) == 1)
        #expect(intensity.value(at: start.addingTimeInterval(Animations.slow)) == 0)
        #expect(
            intensity.value(at: start.addingTimeInterval(Animations.slow * 0.5)) > 0
                && intensity.value(at: start.addingTimeInterval(Animations.slow * 0.5)) < 1
        )
    }

    @Test func settledStatesAreFlat() {
        #expect(MorphIntensity.full.value(at: .now) == 1)
        #expect(MorphIntensity.none.value(at: .now) == 0)
    }

    @Test func clampsBeforeTheChange() {
        #expect(MorphIntensity(engaged: true, changedAt: start).value(at: start - 5) == 0)
        #expect(MorphIntensity(engaged: false, changedAt: start).value(at: start - 5) == 1)
    }

    @Test func transitionResumesFromCurrentValue() {
        // Thinking for a while, then speaking starts mid-ramp-up.
        let thinking = MorphIntensity(engaged: true, changedAt: start)
        let checkpoint = start.addingTimeInterval(Animations.slow * 0.25)
        let speaking = thinking.transitioned(to: false, at: checkpoint)
        #expect(speaking.value(at: checkpoint) == thinking.value(at: checkpoint))
        // It eases the rest of the way down without ever rising again.
        var previous = speaking.value(at: checkpoint)
        for step in stride(
            from: checkpoint + 0.01, to: checkpoint + 1, by: 0.01
        ) {
            let value = speaking.value(at: step)
            #expect(
                value <= previous,
                "value rose again at +\(step.timeIntervalSince(checkpoint))s"
            )
            previous = value
        }
        #expect(speaking.value(at: checkpoint + 1) == 0)
    }

    @Test func listeningFromSpeakingNeverShowsTheWobble() {
        // The reported glitch: speaking (already calm) -> listening would
        // briefly ramp back up to the wobble. Now it stays a still circle.
        let thinking = MorphIntensity(engaged: true, changedAt: start)
        let speaking = thinking.transitioned(to: false, at: start)
        let calm = start.addingTimeInterval(1)
        #expect(speaking.value(at: calm) == 0)
        let listening = speaking.transitioned(to: false, at: calm)
        for step in stride(from: calm, to: calm + 0.5, by: 0.05) {
            #expect(
                listening.value(at: step) == 0,
                "wobble reappeared at +\(step.timeIntervalSince(calm))s"
            )
        }
    }
}

struct MorphFigureTests {
    private let forms = MorphForm.all
    private let pose = MorphTimeline.Pose(from: 2, to: 3, progress: 0.4)

    @Test func zeroRendersExactlyTheRestingCircle() {
        let figure = MorphFigure.of(forms: forms, pose: pose, intensity: 0)
        #expect(figure.points == forms[0].points)
        #expect(abs(figure.width - forms[0].size.width) < 0.000_001)
        #expect(abs(figure.height - forms[0].size.height) < 0.000_001)
    }

    @Test func oneRendersExactlyTheSeededPose() {
        let figure = MorphFigure.of(forms: forms, pose: pose, intensity: 1)
        let expected = stride(from: 0.0, to: Double(MorphForm.pointCount), by: 1).allSatisfy { i in
            let a = forms[pose.from].points[Int(i)]
            let b = forms[pose.to].points[Int(i)]
            let x = a.x + (b.x - a.x) * pose.progress
            let y = a.y + (b.y - a.y) * pose.progress
            let drawn = figure.points[Int(i)]
            return abs(drawn.x - x) < 0.000_001 && abs(drawn.y - y) < 0.000_001
        }
        #expect(expected)
    }

    @Test func intensityClamps() {
        let held = MorphFigure.of(forms: forms, pose: pose, intensity: 0)
        #expect(MorphFigure.of(forms: forms, pose: pose, intensity: -5) == held)
        #expect(MorphFigure.of(forms: forms, pose: pose, intensity: 12) == MorphFigure
            .of(forms: forms, pose: pose, intensity: 1))
    }
}
