import Foundation

/// What Pictr hands its widget through the App Group: On This Day counts for the coming
/// days, the streak and queue, and the day a small photo was saved beside it. The app
/// writes it; the widget only reads it and never touches Photos.
struct WidgetFeed: Codable, Equatable, Sendable {
    /// A calendar day stored as numbers, not a moment, so the feed still means the same
    /// dates after the iPhone changes time zone.
    struct DayKey: Codable, Hashable, Sendable {
        var year: Int
        var month: Int
        var day: Int

        init(_ date: Date, calendar: Calendar = .current) {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            year = parts.year ?? 0
            month = parts.month ?? 0
            day = parts.day ?? 0
        }

        func start(in calendar: Calendar = .current) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
    }

    struct Day: Codable, Equatable, Sendable {
        var day: DayKey
        var photoCount: Int
        var years: Int
    }

    /// What the widget shows on one day.
    struct Shown: Equatable, Sendable {
        var date: Date
        /// Nil past the days the app counted; the widget then asks to open Pictr.
        var photoCount: Int?
        var years: Int
        var streak: Int
        var reviewedToday: Int
        var queued: Int
        var showsPhoto: Bool
        var isWeek: Bool
    }

    static let appGroup = "group.cloud.acker.pictr"
    static let kind = "OnThisDay"
    /// Days counted ahead, today included.
    static let horizon = 7

    var days: [Day] = []
    var isWeek = false
    var streak = 0
    var reviewedToday = 0
    /// The day `streak` and `reviewedToday` were counted on.
    var statsDay: DayKey?
    var queued = 0
    /// The day the saved photo belongs to. It is shown on that day only.
    var photoDay: DayKey?
    /// The photo's asset, so it can be dropped once it is queued or deleted.
    var photoID: String?

    func shown(on date: Date, calendar: Calendar = .current) -> Shown {
        let day = calendar.startOfDay(for: date)
        let key = DayKey(date, calendar: calendar)
        let counted = days.first { $0.day == key }
        let gap = statsDay?.start(in: calendar).flatMap { calendar.dateComponents([.day], from: $0, to: day).day }
        // A streak runs through yesterday, so it lasts one more day only if that day had reviews.
        let streakShown: Int
        switch gap {
        case let gap? where gap <= 0: streakShown = streak
        case 1? where reviewedToday > 0: streakShown = streak
        default: streakShown = 0
        }
        return Shown(date: day, photoCount: counted?.photoCount, years: counted?.years ?? 0,
                     streak: streakShown, reviewedToday: (gap ?? 1) <= 0 ? reviewedToday : 0, queued: queued,
                     showsPhoto: photoDay == key, isWeek: isWeek)
    }

    /// Now, then each midnight through the one after the last counted day.
    func timelineDates(from now: Date, calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        guard let last = days.compactMap({ $0.day.start(in: calendar) }).max(),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return dates }
        var day = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next <= end {
            dates.append(next)
            day = next
        }
        return dates
    }

    /// Library/Application Support/Widget in the App Group, like the app's own data.
    static var directory: URL? {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let directory = root.appending(path: "Library/Application Support/Widget", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    static var feedURL: URL? { directory?.appending(path: "widget-feed.json") }
    static var photoURL: URL? { directory?.appending(path: "widget-photo.jpg") }

    static func load(from url: URL? = feedURL) -> WidgetFeed? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetFeed.self, from: data)
    }

    func save(to url: URL? = Self.feedURL) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
