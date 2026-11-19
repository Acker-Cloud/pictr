import Foundation
import Testing
@testable import Pictr

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

private func key(_ y: Int, _ m: Int, _ d: Int) -> WidgetFeed.DayKey {
    WidgetFeed.DayKey(day(y, m, d), calendar: utc)
}

@Suite struct WidgetFeedTests {
    private var feed: WidgetFeed {
        var feed = WidgetFeed()
        feed.days = [
            .init(day: key(2026, 11, 19), photoCount: 14, years: 4),
            .init(day: key(2026, 11, 20), photoCount: 0, years: 0),
            .init(day: key(2026, 11, 21), photoCount: 3, years: 1),
        ]
        feed.streak = 7
        feed.reviewedToday = 12
        feed.statsDay = key(2026, 11, 19)
        feed.queued = 4
        feed.photoDay = key(2026, 11, 19)
        feed.photoID = "hero"
        return feed
    }

    @Test func todayShowsEverything() {
        let shown = feed.shown(on: day(2026, 11, 19, hour: 15), calendar: utc)
        #expect(shown.photoCount == 14)
        #expect(shown.years == 4)
        #expect(shown.streak == 7)
        #expect(shown.reviewedToday == 12)
        #expect(shown.queued == 4)
        #expect(shown.showsPhoto)
    }

    @Test func tomorrowKeepsAStreakTodayEarnedButNotThePhoto() {
        let shown = feed.shown(on: day(2026, 11, 20), calendar: utc)
        #expect(shown.photoCount == 0)
        #expect(shown.streak == 7)
        #expect(shown.reviewedToday == 0)
        #expect(!shown.showsPhoto)
    }

    @Test func aStreakLapsesWithoutReviews() {
        var idle = feed
        idle.reviewedToday = 0
        #expect(idle.shown(on: day(2026, 11, 20), calendar: utc).streak == 0)
        // Even a day with reviews only carries the streak one day forward.
        #expect(feed.shown(on: day(2026, 11, 21), calendar: utc).streak == 0)
    }

    @Test func pastTheCountedDaysAsksToOpenPictr() {
        #expect(feed.shown(on: day(2026, 11, 25), calendar: utc).photoCount == nil)
    }

    @Test func timelineFlipsAtEachMidnightAndOncePastTheLastDay() {
        let now = day(2026, 11, 19, hour: 15)
        #expect(feed.timelineDates(from: now, calendar: utc) == [now, day(2026, 11, 20), day(2026, 11, 21), day(2026, 11, 22)])
        #expect(WidgetFeed().timelineDates(from: now, calendar: utc) == [now])
    }

    @Test func daysMeanTheSameDatesAfterChangingTimeZone() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 10:00 on Nov 19 in Los Angeles is still Nov 19 for the widget.
        let morning = la.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
        let shown = feed.shown(on: morning, calendar: la)
        #expect(shown.photoCount == 14)
        #expect(shown.showsPhoto)
        #expect(shown.streak == 7)
        #expect(feed.timelineDates(from: morning, calendar: la).last == la.date(from: DateComponents(year: 2026, month: 11, day: 22)))
    }

    @Test func noStatsYetMeansNoStreak() {
        var fresh = feed
        fresh.statsDay = nil
        #expect(fresh.shown(on: day(2026, 11, 19), calendar: utc).streak == 0)
    }

    @Test func roundTripsThroughAFile() {
        let url = FileManager.default.temporaryDirectory.appending(path: "feed-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        feed.save(to: url)
        #expect(WidgetFeed.load(from: url) == feed)
    }

    @Test @MainActor func widgetLinksOpenTodayOrShuffle() {
        #expect(AppRouter.destination(for: URL(string: "pictr://today")!) == .init(tab: .today, shuffle: false))
        #expect(AppRouter.destination(for: URL(string: "pictr://shuffle")!) == .init(tab: .today, shuffle: true))
        #expect(AppRouter.destination(for: URL(string: "https://example.com/today")!) == nil)
        #expect(AppRouter.destination(for: URL(string: "pictr://elsewhere")!) == nil)
    }
}
