import Foundation
import CoreGraphics

/// Whether the current login session owns the active console (i.e. is the
/// foreground user, not switched out via fast user switching).
public enum SessionState {
    public static func isOnConsole() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return true // assume foreground if we can't tell (counts time — conservative for limiting)
        }
        // The runtime key in this dictionary is "kCGSSessionOnConsoleKey" (double S).
        // Use literals to avoid depending on a possibly-unexported CoreGraphics constant.
        let keys = ["kCGSSessionOnConsoleKey", "kCGSessionOnConsoleKey"]
        for key in keys {
            if let value = dict[key] as? Bool { return value }
            if let number = dict[key] as? NSNumber { return number.boolValue }
        }
        return true
    }
}
