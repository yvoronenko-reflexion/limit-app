import Foundation
import IOKit

/// System-wide user idle time (seconds since the last keyboard/mouse input), read from
/// IOKit's IOHIDSystem `HIDIdleTime` property. Chosen over
/// CGEventSourceSecondsSinceLastEventType because it needs no Accessibility permission.
public enum IdleTime {
    public static func seconds() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOHIDSystem"),
                                           &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any],
              let nanos = dict["HIDIdleTime"] as? NSNumber else {
            return 0
        }
        return nanos.doubleValue / 1_000_000_000.0
    }
}
