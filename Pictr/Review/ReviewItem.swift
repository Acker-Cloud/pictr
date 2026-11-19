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


/// How much of the calendar On This Day covers in each earlier year.
enum OnThisDayRange: String, CaseIterable, Identifiable, Sendable {
    case day, week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "This day"
        case .week: "This week"
        }
    }

    /// For copy: "from this day in past years".
    var phrase: String {
        switch self {
        case .day: "this day"
        case .week: "this week"
        }
    }
}

enum OnThisDay {
    /// Today's date in each earlier year back to `earliestYear`, newest first. A day
    /// range covers that day; Feb 29 only appears in leap years. A week range covers
    /// the seven days centred on it, and exists every year (Feb 29 centres on Mar 1).
    static func windows(on today: Date, earliestYear: Int, range: OnThisDayRange = .day,
                        calendar: Calendar = .current) -> [DateInterval] {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        // A week near New Year reaches into the year after its own, so one more year back
        // can still hold the earliest photo.
        let oldest = range == .week ? earliestYear - 1 : earliestYear
        guard let thisYear = parts.year, let month = parts.month, let day = parts.day,
              oldest < thisYear
        else { return [] }
        return stride(from: thisYear - 1, through: oldest, by: -1).compactMap { year in
            guard let centre = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            switch range {
            case .day:
                guard calendar.component(.month, from: centre) == month,
                      calendar.component(.day, from: centre) == day,
                      let end = calendar.date(byAdding: .day, value: 1, to: centre)
                else { return nil }
                return DateInterval(start: centre, end: end)
            case .week:
                guard let start = calendar.date(byAdding: .day, value: -3, to: centre),
                      let end = calendar.date(byAdding: .day, value: 4, to: centre),
                      calendar.component(.year, from: end.addingTimeInterval(-1)) >= earliestYear
                else { return nil }
                return DateInterval(start: start, end: end)
            }
        }
    }

    /// Whole years between the photo and today, ignoring time of day. Three days of slack
    /// so the far edge of a week window, even across New Year, still reads "1 year ago".
    static func yearsAgo(_ date: Date?, from today: Date, calendar: Calendar = .current) -> Int? {
        guard let date,
              let end = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: today))
        else { return nil }
        return calendar.dateComponents([.year], from: calendar.startOfDay(for: date), to: end).year
    }
}
