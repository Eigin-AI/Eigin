import CoreGraphics
import Foundation

/// The droplets around the release. Through the last breath they fall in from
/// beyond the screen, faster and faster, and the blob swallows each one: the
/// agent gathering itself. On the release a crown of them splashes off.
///
/// Ported from the design gallery's `onboarding/droplets.ts`, with the same
/// seeded random, so both fall the same way.
enum HatchDroplets {
    struct Droplet {
        let centre: CGPoint
        /// Half-length along the way it travels, and half-width across it.
        let long: Double
        let wide: Double
        /// The way it travels, in radians.
        let angle: Double
        let opacity: Double
        /// How much of the brand colour it has taken on, 0–1.
        let tint: Double
    }

    private struct Falling {
        let lands: Double
        let starts: Double
        let travel: Double
        let from: Double
        let angle: Double
        let curl: Double
        let size: Double
    }

    private struct Thrown {
        let angle: Double
        let life: Double
        let reach: Double
        let size: Double
    }

    /// The droplets falling in and the crown, in units of the blob's radius.
    /// Built in one pass over the random, in the gallery's order.
    private static let (falling, thrown): ([Falling], [Thrown]) = {
        var random = Mulberry32(seed: 0xD209)
        let release = HatchTimeline.release
        let falling = (0 ..< 16).map { i in
            // More and more of them, the closer the release: the last lands just before it.
            let lands = release - 0.04 - 1.15 * pow((Double(i) + random() * 0.6) / 16, 1.6)
            let travel = 0.7 + 0.25 * random()
            let from = 0.85 + 0.15 * random()
            let angle = Double(i) * 2.39996 + random() * 0.4
            let side: Double = random() < 0.5 ? -1 : 1
            let curl = side * (0.3 + 0.3 * random())
            let size = 0.05 + 0.08 * random()
            return Falling(
                lands: lands, starts: lands - travel, travel: travel,
                from: from, angle: angle, curl: curl, size: size
            )
        }
        let thrown = (0 ..< 9).map { i in
            let angle = Double(i) / 9 * 2 * .pi + random() * 0.5
            let life = 0.4 + 0.15 * random()
            let reach = 1.5 + 0.6 * random()
            let size = 0.05 + 0.05 * random()
            return Thrown(angle: angle, life: life, reach: reach, size: size)
        }
        return (falling, thrown)
    }()

    /// The droplets falling in at `t`, in points from the blob's centre. They
    /// set off `reach` points out, past the edge of the screen.
    static func gathering(_ t: TimeInterval, radius: Double, reach: Double) -> [Droplet] {
        falling.compactMap { drop in
            let p = (t - drop.starts) / drop.travel
            guard p > 0, p < 1 else { return nil }
            let from = reach * drop.from
            // Falls in like into a well: slow far out, fastest as it lands.
            let distance = radius + (from - radius) * (1 - pow(p, 2.4))
            let speed = (from - radius) * 2.4 * pow(p, 1.4) / drop.travel
            let angle = drop.angle + drop.curl * pow(1 - p, 2)
            let stretch = 1 + min(2.5, speed / 900)
            let size = radius * drop.size * (1 - 0.4 * HatchTimeline.clamp((p - 0.9) / 0.1))
            return Droplet(
                centre: CGPoint(x: distance * cos(angle), y: distance * sin(angle)),
                long: size * stretch,
                wide: size / sqrt(stretch),
                angle: angle,
                opacity: HatchTimeline.clamp(p / 0.15),
                // Muted out in the world, the brand colour by the time it lands.
                tint: pow(p, 1.5)
            )
        }
    }

    /// How far the blob's edge at `angle` reaches out to swallow droplets: it
    /// necks out to meet each one as it lands, then draws it in. In units of
    /// its radius.
    static func swallowing(_ t: TimeInterval, angle: Double) -> Double {
        falling.reduce(0) { sum, drop in
            let since = t - drop.lands
            guard since >= -0.08, since <= 0.4 else { return sum }
            let envelope = since < 0 ? 1 + since / 0.08 : exp(-since / 0.1)
            let away = atan2(sin(angle - drop.angle), cos(angle - drop.angle))
            return sum + 1.6 * drop.size * envelope * exp(-pow(away / 0.32, 2))
        }
    }

    /// The crown splashing off the blob on the release, in points from its centre.
    static func splash(_ t: TimeInterval, radius: Double) -> [Droplet] {
        thrown.compactMap { drop in
            let p = (t - HatchTimeline.release - 0.02) / drop.life
            guard p > 0, p < 1 else { return nil }
            let distance = radius * (0.95 + (drop.reach - 0.95) * HatchTimeline.easeOut(p))
            let stretch = 1 + 1.8 * pow(1 - p, 2)
            let size = radius * drop.size * pow(1 - p, 0.8)
            return Droplet(
                centre: CGPoint(x: distance * cos(drop.angle), y: distance * sin(drop.angle)),
                long: size * stretch,
                wide: size / sqrt(stretch),
                angle: drop.angle,
                opacity: HatchTimeline.clamp((1 - p) / 0.3),
                tint: 1
            )
        }
    }
}

/// The gallery's seeded random (mulberry32), bit for bit.
private struct Mulberry32 {
    var seed: UInt32

    mutating func callAsFunction() -> Double {
        seed = seed &+ 0x6D2B_79F5
        var x = (seed ^ (seed >> 15)) &* (seed | 1)
        x ^= x &+ ((x ^ (x >> 7)) &* (x | 61))
        return Double(x ^ (x >> 14)) / 4_294_967_296
    }
}
