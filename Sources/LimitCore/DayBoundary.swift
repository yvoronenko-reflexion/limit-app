import Foundation

/// Maps an instant to a "budget day" key (yyyy-MM-dd), where the day rolls over at a
/// configurable local time. The key is the calendar date of the most recent reset
/// instant at or before the given date.
///
/// Using a date-string key (rather than storing the reset `Date`) keeps state files
/// timezone- and DST-robust: a key only changes when a reset boundary is crossed.
public struct DayBoundary {
    public var resetHour: Int
    public var resetMinute: Int
    public var calendar: Calendar

    public init(resetHour: Int, resetMinute: Int, calendar: Calendar = .current) {
        self.resetHour = resetHour
        self.resetMinute = resetMinute
        self.calendar = calendar
    }

    public func dayKey(for date: Date) -> String {
        let startOfDay = calendar.startOfDay(for: date)
        let todayReset = calendar.date(
            bySettingHour: resetHour, minute: resetMinute, second: 0,
            of: startOfDay, matchingPolicy: .nextTime
        ) ?? startOfDay

        let boundary = date >= todayReset
            ? todayReset
            : (calendar.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset)

        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: boundary)
    }
}
