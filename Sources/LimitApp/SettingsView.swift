import SwiftUI
import LimitCore

/// Settings are gated behind the parent PIN. If no PIN exists yet, the parent is asked
/// to create one first.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var unlocked = false

    var body: some View {
        Group {
            if !model.isPINSet() {
                CreatePINView(model: model, unlocked: $unlocked)
            } else if !unlocked {
                UnlockView(model: model, unlocked: $unlocked)
            } else {
                SettingsFormView(model: model)
            }
        }
        .padding(20)
        .frame(width: 460)
        // The Settings scene's view stays alive across open/close, so `unlocked`
        // would persist and skip the PIN on the second open. Re-lock on close.
        .onDisappear { unlocked = false }
    }
}

private struct CreatePINView: View {
    @ObservedObject var model: AppModel
    @Binding var unlocked: Bool
    @State private var pin = ""
    @State private var confirm = ""
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Set a parent PIN", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            Text("Required to open settings, and to unlock or add time when the day's screen time runs out.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("New PIN (4+ digits)", text: $pin)
            SecureField("Confirm PIN", text: $confirm)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            Button("Save PIN") {
                guard pin.count >= 4 else { error = "Use at least 4 characters."; return }
                guard pin == confirm else { error = "PINs don't match."; return }
                model.setPIN(pin)
                unlocked = true
            }
            .disabled(pin.isEmpty || confirm.isEmpty)
        }
    }
}

private struct UnlockView: View {
    @ObservedObject var model: AppModel
    @Binding var unlocked: Bool
    @State private var pin = ""
    @State private var error = ""
    /// Seconds of brute-force cooldown remaining after a wrong PIN; >0 disables entry.
    @State private var cooldown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Enter parent PIN", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            SecureField("PIN", text: $pin).onSubmit(attempt).disabled(cooldown > 0)
            if cooldown > 0 {
                Text("Too many tries — wait \(cooldown)s.").font(.caption).foregroundStyle(.red)
            } else if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Unlock", action: attempt).disabled(pin.isEmpty || cooldown > 0)
        }
    }

    private func attempt() {
        guard cooldown == 0 else { return }
        if model.verifyPIN(pin) {
            unlocked = true
        } else {
            error = "Incorrect PIN."
            pin = ""
            cooldown = 5
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                cooldown -= 1
                if cooldown <= 0 { timer.invalidate() }
            }
        }
    }
}

private struct SettingsFormView: View {
    @ObservedObject var model: AppModel
    @State private var draft: LimitCore.Settings
    @State private var handlesText: String
    @State private var changePIN = false
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var pinError: String?
    @State private var saved = false

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.settings)
        _handlesText = State(initialValue: model.settings.parentHandles.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section {
                Stepper("\(draft.dailyLimitSeconds / 60) minutes",
                        value: $draft.dailyLimitSeconds,
                        in: 15 * 60 ... 12 * 60 * 60, step: 15 * 60)
            } header: { Label("Daily limit", systemImage: "clock.fill") }
            Section {
                HStack {
                    Text("Remaining today")
                    Spacer()
                    Text(AppModel.format(seconds: model.remainingSeconds)).monospacedDigit()
                }
                HStack {
                    Button("+15 min") { model.extend(by: 15 * 60) }
                    Button("+30 min") { model.extend(by: 30 * 60) }
                }
                Text("Adds time to today only — doesn't change the daily limit. Logged as an extension in usage history.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Today's time", systemImage: "plus.circle.fill") }
            Section {
                Stepper("Hour: \(draft.resetHour)", value: $draft.resetHour, in: 0 ... 23)
                Stepper("Minute: \(draft.resetMinute)", value: $draft.resetMinute, in: 0 ... 59, step: 5)
            } header: { Label("Daily reset time", systemImage: "sunrise.fill") }
            Section {
                Stepper("Pause after \(draft.idleThresholdSeconds)s of no input",
                        value: $draft.idleThresholdSeconds, in: 15 ... 600, step: 15)
            } header: { Label("Idle pause", systemImage: "moon.zzz.fill") }
            Section {
                Toggle("Lock the screen when time runs out", isOn: $draft.enforcementEnabled)
                Text("Shows a full-screen overlay at 0 that only a parent can dismiss (by PIN). Install the watchdog (see scripts/) so quitting the app can't bypass it.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Enforcement", systemImage: "lock.shield.fill") }
            Section {
                TextField("phone/email, comma-separated", text: $handlesText)
            } header: { Label("Parents' iMessage handles (used in a later version)", systemImage: "message.fill") }
            Section {
                TextField("username", text: $draft.targetUsername)
            } header: { Label("Target macOS user", systemImage: "person.fill") }
            Section {
                Toggle("Change PIN", isOn: $changePIN)
                if changePIN {
                    SecureField("New PIN (4+ chars)", text: $newPIN)
                    SecureField("Confirm new PIN", text: $confirmPIN)
                    if let pinError {
                        Text(pinError).font(.caption).foregroundStyle(.red)
                    }
                }
            } header: { Label("Parent PIN", systemImage: "key.fill") }
            HStack {
                Button { save() } label: { Label("Save", systemImage: "checkmark.circle.fill") }
                if saved {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 560)
    }

    private func save() {
        if changePIN {
            guard newPIN.count >= 4 else { pinError = "Use at least 4 characters."; return }
            guard newPIN == confirmPIN else { pinError = "PINs don't match."; return }
        }

        var updated = draft
        updated.parentHandles = handlesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        model.updateSettings(updated)

        if changePIN {
            model.setPIN(newPIN)
            newPIN = ""
            confirmPIN = ""
            pinError = nil
            changePIN = false
        }
        saved = true
    }
}
