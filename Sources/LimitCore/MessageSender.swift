import Foundation

/// Sends one-way iMessages to the parents' handles by driving Messages.app via AppleScript
/// (`osascript`). Best-effort and fire-and-forget: every failure mode — no Automation
/// permission, Messages not signed in, an unreachable handle — is swallowed so a failed
/// notification can never wedge the 1 Hz tick. Requires the (non-sandboxed) app to be
/// allowed to control Messages and the child's session to be signed into iMessage.
public final class MessageSender {
    private let queue = DispatchQueue(label: "com.yscale.limit.imessage", qos: .utility)

    public init() {}

    /// Send `body` to each handle. Returns immediately; the AppleScript runs off the main
    /// thread, one handle at a time.
    public func send(_ body: String, to handles: [String]) {
        let clean = handles
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !clean.isEmpty, !body.isEmpty else { return }
        queue.async {
            for handle in clean { Self.run(body: body, handle: handle) }
        }
    }

    /// The AppleScript program. The handle and body are passed as `argv`, never spliced into
    /// the source, so the message text needs no escaping and can't break the script.
    static let script = """
    on run argv
        set theHandle to item 1 of argv
        set theBody to item 2 of argv
        tell application "Messages"
            set theService to 1st account whose service type = iMessage
            set theBuddy to participant theHandle of theService
            send theBody to theBuddy
        end tell
    end run
    """

    private static func run(body: String, handle: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script, handle, body]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // Messages unavailable / not permitted — nothing actionable here.
        }
    }
}
