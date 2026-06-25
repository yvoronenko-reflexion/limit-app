import SwiftUI

/// A friendly visual "mood" for the remaining budget. It maps how much time is left to a
/// playful SF Symbol, a color, and an encouraging blurb, so the app reads as cheerful
/// rather than punitive. Purely cosmetic — no behavior depends on it.
///
/// The metaphor is a day: lots of time = sunny, winding down = cloudy/hourglass, finished
/// = a calm night sky ("see you tomorrow").
enum TimeMood {
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
                Image(systemName: mood.symbol)
                    .font(.system(size: size * 0.22))
                    .symbolRenderingMode(.multicolor)
                Text(AppModel.format(seconds: remaining))
                    .font(.system(size: size * 0.19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
    }
}
