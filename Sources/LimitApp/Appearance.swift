import SwiftUI

/// A friendly visual "mood" for the remaining budget. It maps how much time is left to a
/// playful SF Symbol, a color, and an encouraging blurb, so the app reads as cheerful
/// rather than punitive. Purely cosmetic — no behavior depends on it.
///
/// The metaphor is a day: lots of time = sunny, winding down = cloudy/hourglass, finished
/// = a calm night sky ("see you tomorrow").
enum TimeMood: Equatable {
    case plenty   // sunny
    case good     // partly cloudy
    case low      // almost out
    case out      // done for today

    /// Pick a mood from the remaining seconds and the day's limit. The `low` cutoff
    /// matches the 5-minute warning so the glyph and the notifications agree.
    static func make(remaining: Int, limit: Int) -> TimeMood {
        if remaining <= 0 { return .out }
        if remaining <= 300 { return .low }
        let fraction = limit > 0 ? Double(remaining) / Double(limit) : 1
        return fraction >= 0.5 ? .plenty : .good
    }

    var symbol: String {
        switch self {
        case .plenty: return "sun.max.fill"
        case .good:   return "cloud.sun.fill"
        case .low:    return "hourglass"
        case .out:    return "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .plenty: return .yellow
        case .good:   return .teal
        case .low:    return .orange
        case .out:    return .indigo
        }
    }

    var blurb: String {
        switch self {
        case .plenty: return "Lots of time to play"
        case .good:   return "Plenty of time left"
        case .low:    return "Almost out of time"
        case .out:    return "All done for today"
        }
    }
}

/// A circular progress ring with the mood glyph + countdown in the center — the cheerful
/// centerpiece of the menu dropdown.
struct BudgetRing: View {
    let remaining: Int
    let limit: Int
    var size: CGFloat = 124

    private var mood: TimeMood { .make(remaining: remaining, limit: limit) }
    private var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, Double(remaining) / Double(limit)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(mood.color.opacity(0.15), lineWidth: size * 0.085)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(mood.color, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 2) {
                // `.id(mood)` gives a fresh view (with `animate` reset to false) whenever the
                // mood changes, so its entry animation re-triggers instead of freezing.
                MoodGlyph(mood: mood, size: size * 0.22)
                    .id(mood)
                Text(AppModel.format(seconds: remaining))
                    .font(.system(size: size * 0.19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The animated center glyph. Each mood gets a gentle, "natural" motion rather than a
/// uniform pulse: the sun slowly turns, a cloud drifts across the partly-sunny sky, the
/// hourglass tips as if its sand is running, and the night-sky moon bobs softly. Purely
/// cosmetic. A single `animate` flag is flipped on appear so each `repeatForever` has two
/// states to ease between.
struct MoodGlyph: View {
    let mood: TimeMood
    let size: CGFloat

    @State private var animate = false

    var body: some View {
        glyph
            .symbolRenderingMode(.multicolor)
            .frame(width: size * 1.6, height: size * 1.6)
            .onAppear { animate = true }
    }

    @ViewBuilder private var glyph: some View {
        switch mood {
        case .plenty:
            // The sun slowly turns; its rays make the rotation read clearly.
            Image(systemName: "sun.max.fill")
                .font(.system(size: size))
                .rotationEffect(.degrees(animate ? 360 : 0))
                .animation(.linear(duration: 22).repeatForever(autoreverses: false), value: animate)
        case .good:
            // A cloud drifts back and forth across a (gently turning) sun.
            ZStack {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: size * 0.9))
                    .offset(x: -size * 0.1, y: -size * 0.08)
                    .rotationEffect(.degrees(animate ? 360 : 0))
                    .animation(.linear(duration: 30).repeatForever(autoreverses: false), value: animate)
                Image(systemName: "cloud.fill")
                    .font(.system(size: size * 0.78))
                    .offset(x: animate ? size * 0.22 : -size * 0.22, y: size * 0.12)
                    .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animate)
            }
        case .low:
            // The hourglass tips over, as if turned to let the last sand run.
            Image(systemName: "hourglass")
                .font(.system(size: size))
                .rotationEffect(.degrees(animate ? 180 : 0))
                .animation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true), value: animate)
        case .out:
            // The moon bobs softly in the night sky.
            Image(systemName: "moon.stars.fill")
                .font(.system(size: size))
                .offset(y: animate ? -size * 0.06 : size * 0.06)
                .animation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true), value: animate)
        }
    }
}

/// A drifting field of softly twinkling stars, used as the backdrop of the "all done"
/// lock overlay. Positions and timing are randomized once on appear and held in state so
/// they stay put across redraws; a single `twinkle` toggle drives every star, but each has
/// its own period and phase delay so they shimmer out of sync. Purely decorative.
struct StarField: View {
    var count = 70

    private struct Star: Identifiable {
        let id = UUID()
        let x: CGFloat       // 0...1, relative to width
        let y: CGFloat       // 0...1, relative to height (kept high in the sky)
        let size: CGFloat
        let period: Double
        let delay: Double
        let dim: Double      // faintest opacity at the bottom of its twinkle
    }

    @State private var stars: [Star] = []
    @State private var twinkle = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(stars) { star in
                    Circle()
                        .fill(.white)
                        .frame(width: star.size, height: star.size)
                        .position(x: star.x * geo.size.width, y: star.y * geo.size.height)
                        .opacity(twinkle ? 0.95 : star.dim)
                        .scaleEffect(twinkle ? 1.0 : 0.6)
                        .blur(radius: 0.3)
                        .animation(.easeInOut(duration: star.period)
                            .repeatForever(autoreverses: true).delay(star.delay), value: twinkle)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if stars.isEmpty {
                stars = (0..<count).map { _ in
                    Star(x: .random(in: 0...1),
                         y: .random(in: 0...0.75),
                         size: .random(in: 1.2...3.0),
                         period: .random(in: 1.4...3.6),
                         delay: .random(in: 0...2.0),
                         dim: .random(in: 0.05...0.3))
                }
            }
            twinkle = true
        }
    }
}

/// The friendly moon for the lock overlay: it bobs, sways, and glows so the "see you
/// tomorrow" screen feels calm and alive rather than like a stern lockout.
struct FloatingMoon: View {
    var size: CGFloat

    @State private var float = false

    var body: some View {
        Image(systemName: "moon.stars.fill")
            .font(.system(size: size))
            .symbolRenderingMode(.multicolor)
            .shadow(color: .yellow.opacity(0.45), radius: float ? 22 : 12)
            .offset(y: float ? -8 : 8)
            .rotationEffect(.degrees(float ? 5 : -5))
            .symbolEffect(.pulse, options: .repeating)
            .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: float)
            .onAppear { float = true }
    }
}
