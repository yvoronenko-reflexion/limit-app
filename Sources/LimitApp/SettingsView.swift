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
        .frame(width: 400)
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
            Text("Set a parent PIN").font(.headline)
            Text("Required to open settings, and (in a later version) to unlock or extend time.")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter parent PIN").font(.headline)
            SecureField("PIN", text: $pin).onSubmit(attempt)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            Button("Unlock", action: attempt).disabled(pin.isEmpty)
        }
    }

    private func attempt() {
        if model.verifyPIN(pin) {
            unlocked = true
        } else {
            error = "Incorrect PIN."
            pin = ""
        }
    }
}

private struct SettingsFormView: View {
    @ObservedObject var model: AppModel
    @State private var draft: LimitCore.Settings
    @State private var handlesText: String
    @State private var changePIN = false
    @State private var newPIN = ""
    @State private var saved = false

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.settings)
        _handlesText = State(initialValue: model.settings.parentHandles.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section("Daily limit") {
                Stepper("\(draft.dailyLimitSeconds / 60) minutes",
                        value: $draft.dailyLimitSeconds,
                        in: 15 * 60 ... 12 * 60 * 60, step: 15 * 60)
            }
            Section("Daily reset time") {
                Stepper("Hour: \(draft.resetHour)", value: $draft.resetHour, in: 0 ... 23)
                Stepper("Minute: \(draft.resetMinute)", value: $draft.resetMinute, in: 0 ... 59, step: 5)
            }
            Section("Idle pause") {
                Stepper("Pause after \(draft.idleThresholdSeconds)s of no input",
                        value: $draft.idleThresholdSeconds, in: 15 ... 600, step: 15)
            }
            Section("Parents' iMessage handles (used in a later version)") {
                TextField("phone/email, comma-separated", text: $handlesText)
            }
            Section("Target macOS user") {
                TextField("username", text: $draft.targetUsername)
            }
            Section("Parent PIN") {
                Toggle("Change PIN", isOn: $changePIN)
                if changePIN {
                    SecureField("New PIN (4+ chars)", text: $newPIN)
                }
            }
            HStack {
                Button("Save", action: save)
                if saved {
                    Text("Saved").font(.caption).foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        var updated = draft
        updated.parentHandles = handlesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        model.updateSettings(updated)

        if changePIN, newPIN.count >= 4 {
            model.setPIN(newPIN)
            newPIN = ""
            changePIN = false
        }
        saved = true
    }
}
