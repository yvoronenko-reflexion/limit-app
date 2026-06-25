import SwiftUI

/// The full-screen "time's up" overlay shown when the budget is exhausted. The child
/// can't dismiss it; a parent unlocks (extends time) by entering the parent PIN and
/// choosing how much time to grant. Only the primary screen shows the controls — the
/// other screens just get the dimmed shield.
struct LockOverlayView: View {
    @ObservedObject var model: AppModel
    /// Whether this overlay instance owns the interactive controls (primary screen).
    let showsControls: Bool

    @State private var pin = ""
    @State private var error = ""

    /// Extension presets offered to the parent, in minutes.
    private let presets = [15, 30, 60]

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            if showsControls {
                controls
                    .frame(maxWidth: 420)
                    .padding(40)
            } else {
                Text("Time's up")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 20) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.9))

            Text("Time's up for today")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Screen time has run out. A parent can grant more time by entering the parent PIN.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))

            SecureField("Parent PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit { grant(minutes: presets.first ?? 15) }

            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                ForEach(presets, id: \.self) { mins in
                    Button("+\(mins) min") { grant(minutes: mins) }
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.isEmpty)
                }
            }

            Text("To change limits or the PIN, grant time first, then open Settings from the menu bar.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    private func grant(minutes: Int) {
        guard model.verifyPIN(pin) else {
            error = "Incorrect PIN."
            pin = ""
            return
        }
        pin = ""
        error = ""
        model.extend(by: minutes * 60)
    }
}
