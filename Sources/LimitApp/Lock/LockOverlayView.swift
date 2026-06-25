import SwiftUI

/// The full-screen "all done for today" overlay shown when the budget is exhausted. It's
/// deliberately warm and encouraging rather than a stern lockdown: a calm night-sky
/// gradient, a friendly moon, and a "see you tomorrow" message. The child can't dismiss
/// it; a grown-up can add time by entering the parent PIN and choosing how much. Only the
/// primary screen shows the controls — the other screens just get the friendly backdrop.
struct LockOverlayView: View {
    @ObservedObject var model: AppModel
    /// Whether this overlay instance owns the interactive controls (primary screen).
    let showsControls: Bool

    @State private var pin = ""
    @State private var error = ""
    /// Seconds of brute-force cooldown remaining after a wrong PIN; >0 disables entry.
    @State private var cooldown = 0

    /// Extension presets offered to the parent, in minutes.
    private let presets = [15, 30, 60]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.20, blue: 0.45),
                         Color(red: 0.10, green: 0.12, blue: 0.28)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if showsControls {
                card
                    .frame(maxWidth: 440)
                    .padding(40)
            } else {
                friendlyBanner
            }
        }
    }

    private var friendlyBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.multicolor)
            Text("All done for today")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("See you tomorrow! 🌙")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.multicolor)
                .padding(.bottom, 2)

            Text("All done for today!")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Great job today — screen time is finished. See you tomorrow! 🌙")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            VStack(spacing: 12) {
                Label("Grown-up? You can add some time.", systemImage: "person.badge.key.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("Parent PIN", text: $pin)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .disabled(cooldown > 0)
                    .onSubmit { grant(minutes: presets.first ?? 15) }

                if cooldown > 0 {
                    Text("Too many tries — wait \(cooldown)s.")
                        .font(.caption).foregroundStyle(.red)
                } else if !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    ForEach(presets, id: \.self) { mins in
                        Button { grant(minutes: mins) } label: {
                            Label("\(mins) min", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.isEmpty || cooldown > 0)
                    }
                }
            }

            Text("To change limits or the PIN, add time first, then open Settings from the menu bar.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(radius: 30)
    }

    private func grant(minutes: Int) {
        guard cooldown == 0 else { return }
        guard model.verifyPIN(pin) else {
            error = "That PIN didn't match. Try again."
            pin = ""
            startCooldown()
            return
        }
        pin = ""
        error = ""
        model.extend(by: minutes * 60)
    }

    /// Throttle brute-forcing: disable entry for 5 seconds, counting down once per second.
    private func startCooldown() {
        cooldown = 5
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            cooldown -= 1
            if cooldown <= 0 { timer.invalidate() }
        }
    }
}
