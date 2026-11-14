import Foundation

/// One photo or video in a swipe deck.
struct ReviewItem: Sendable, Identifiable, Hashable {
    var id: String
    var creationDate: Date?
    var mediaKind: AssetMediaKind
    var duration: TimeInterval
    var isFavorite: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    var isLivePhoto: Bool = false
}

/// A calendar month, used to group the library.
struct MonthKey: Sendable, Hashable, Comparable, Identifiable, Codable {
    var year: Int
    var month: Int

    var id: String { String(format: "%04d-%02d", year, month) }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0)
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    func interval(calendar: Calendar = .current) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    func title(calendar: Calendar = .current) -> String {
        guard let start = interval(calendar: calendar)?.start else { return id }
        return start.formatted(.dateTime.month(.wide).year())
    }
}


enum OnThisDay {
    /// Today's month and day in each earlier year back to `earliestYear`, newest first.
    /// Feb 29 only appears in leap years.
    static func windows(on today: Date, earliestYear: Int, calendar: Calendar = .current) -> [DateInterval] {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let thisYear = parts.year, let month = parts.month, let day = parts.day,
              earliestYear < thisYear
        else { return [] }
        return stride(from: thisYear - 1, through: earliestYear, by: -1).compactMap { year in
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.month, from: start) == month,
                  calendar.component(.day, from: start) == day,
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// Calendar years between the photo and today, ignoring time of day.
    static func yearsAgo(_ date: Date?, from today: Date, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        return calendar.component(.year, from: today) - calendar.component(.year, from: date)
    }
}
