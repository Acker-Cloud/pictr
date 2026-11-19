import Foundation
import Testing
@testable import Pictr

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

private func item(_ id: String, favorite: Bool = false, date: Date? = nil) -> ReviewItem {
    ReviewItem(id: id, creationDate: date, mediaKind: .image, duration: 0, isFavorite: favorite, pixelWidth: 1, pixelHeight: 1)
}

@Suite struct OnThisDayTests {
    @Test func windowsCoverEachPastYearNewestFirst() {
        let windows = OnThisDay.windows(on: day(2026, 11, 13), earliestYear: 2023, calendar: utc)
        #expect(windows.map(\.start) == [day(2025, 11, 13), day(2024, 11, 13), day(2023, 11, 13)])
        #expect(windows.allSatisfy { $0.duration == 86_400 })
    }

    @Test func leapDayOnlyInLeapYears() {
        let windows = OnThisDay.windows(on: day(2028, 2, 29), earliestYear: 2019, calendar: utc)
        #expect(windows.map(\.start) == [day(2024, 2, 29), day(2020, 2, 29)])
    }

    @Test func noPastYearsYieldsNothing() {
        #expect(OnThisDay.windows(on: day(2026, 1, 1), earliestYear: 2026, calendar: utc).isEmpty)
    }

    @Test func yearsAgoIgnoresTimeOfDay() {
        let photo = utc.date(from: DateComponents(year: 2025, month: 11, day: 13, hour: 9))!
        #expect(OnThisDay.yearsAgo(photo, from: day(2026, 11, 13), calendar: utc) == 1)
    }

    @Test func weekWindowsCentreOnTheDate() {
        let windows = OnThisDay.windows(on: day(2026, 11, 13), earliestYear: 2024, range: .week, calendar: utc)
        #expect(windows.map(\.start) == [day(2025, 11, 10), day(2024, 11, 10)])
        #expect(windows.allSatisfy { $0.duration == 7 * 86_400 })
    }

    @Test func weekAroundLeapDayExistsInEveryYear() {
        // 2027 has no Feb 29, so its week centres on Mar 1.
        let windows = OnThisDay.windows(on: day(2028, 2, 29), earliestYear: 2026, range: .week, calendar: utc)
        #expect(windows.map(\.start) == [day(2027, 2, 26), day(2026, 2, 26)])
    }

    @Test func yearsAgoFollowsTheWindowAcrossNewYear() {
        // In week mode, Jan 1 2027 shows Dec 29 2025 to Jan 4 2026 as one year ago.
        #expect(OnThisDay.yearsAgo(day(2025, 12, 30), from: day(2027, 1, 1), calendar: utc) == 1)
        #expect(OnThisDay.yearsAgo(day(2023, 11, 13), from: day(2026, 11, 13), calendar: utc) == 3)
        #expect(OnThisDay.yearsAgo(day(2026, 6, 1), from: day(2026, 11, 13), calendar: utc) == 0)
        // Whole years, not rounded: half a year is 0, a year and a half is 1.
        #expect(OnThisDay.yearsAgo(day(2026, 5, 1), from: day(2026, 11, 13), calendar: utc) == 0)
        #expect(OnThisDay.yearsAgo(day(2025, 5, 1), from: day(2026, 11, 13), calendar: utc) == 1)
        // The far edge of a week window still reads one year.
        #expect(OnThisDay.yearsAgo(day(2025, 11, 16), from: day(2026, 11, 13), calendar: utc) == 1)
    }

    @Test func weekNearNewYearReachesTheEarliestPhoto() {
        // The earliest photo is Jan 1 2025; Dec 30 2025's week a year back holds it.
        let windows = OnThisDay.windows(on: day(2025, 12, 30), earliestYear: 2025, range: .week, calendar: utc)
        #expect(windows.map(\.start) == [day(2024, 12, 27)])
        #expect(OnThisDay.windows(on: day(2025, 12, 30), earliestYear: 2025, calendar: utc).isEmpty)
    }

    @Test func monthKeyIntervalAndOrdering() {
        let key = MonthKey(day(2024, 2, 10), calendar: utc)
        #expect(key == MonthKey(year: 2024, month: 2))
        #expect(key.interval(calendar: utc) == DateInterval(start: day(2024, 2, 1), end: day(2024, 3, 1)))
        #expect(MonthKey(year: 2023, month: 12) < key)
    }
}

@Suite struct ReviewSessionTests {
    @Test func decideAdvancesAndUndoRestores() {
        var session = ReviewSession(items: [item("a"), item("b"), item("c")])
        session.decide(.keep)
        session.decide(.trash)
        #expect(session.current?.id == "c")
        #expect(session.keptCount == 1 && session.trashedCount == 1)
        let undone = session.undo()
        #expect(undone == .init(item: item("b"), decision: .trash))
        #expect(session.current?.id == "b")
    }

    @Test func favoriteStepCountsAsKeptAndUndoesInOrder() {
        var session = ReviewSession(items: [item("a"), item("b")])
        session.decide(.keep, favorited: true)
        session.decide(.keep)
        #expect(session.keptCount == 2)
        #expect(session.favoritedCount == 1)
        #expect(session.undo()?.favorited == false)
        #expect(session.undo() == .init(item: item("a"), decision: .keep, favorited: true))
        #expect(session.favoritedCount == 0)
    }

    @Test func finishesAfterLastItem() {
        var session = ReviewSession(items: [item("a")])
        session.decide(.keep)
        #expect(session.isFinished)
        #expect(session.decide(.trash) == nil)
    }
}

@Suite struct DecisionBookTests {
    @Test func favoritesCannotBeQueued() {
        var book = DecisionBook()
        let trashed = book.record(.trash, for: item("fav", favorite: true))
        #expect(!trashed)
        #expect(book.queue.isEmpty)
        let kept = book.record(.keep, for: item("fav", favorite: true))
        #expect(kept)
    }

    @Test func queueIsTrashInDecisionOrder() {
        var book = DecisionBook()
        book.record(.trash, for: item("b"), at: Date(timeIntervalSince1970: 2))
        book.record(.trash, for: item("a"), at: Date(timeIntervalSince1970: 1))
        book.record(.keep, for: item("c"))
        #expect(book.queue == ["a", "b"])
    }

    @Test func bulkQueueSkipsExplicitKeeps() {
        var book = DecisionBook()
        book.record(.keep, for: item("kept"))
        book.queue(ids: ["kept", "new"])
        #expect(book.queue == ["new"])
        #expect(book.decision(for: "kept") == .keep)
    }

    @Test func applyClearsQueueAndLogsOnlySubmitted() {
        var book = DecisionBook()
        book.queue(ids: ["a", "b", "gone"])
        book.finishApply(queued: ["a", "b", "gone"], submitted: ["a", "b"], bytes: 300)
        #expect(book.queue.isEmpty)
        #expect(book.applied.map(\.count) == [2])
        #expect(book.applied.first?.bytes == 300)
    }

    @Test func deletedPhotosStayLabelledForLearning() {
        var book = DecisionBook()
        book.queue(ids: ["a", "gone"])
        book.finishApply(queued: ["a", "gone"], submitted: ["a"], bytes: 1)
        #expect(book.labels["a"] == true)
        #expect(book.labels["gone"] == nil)
        book.forgetLearning()
        #expect(book.labels["a"] == nil)
    }

    @Test func reviewedCountPerMonth() {
        var book = DecisionBook()
        book.record(.keep, for: item("a", date: day(2024, 5, 1)))
        book.record(.trash, for: item("b", date: day(2024, 5, 20)))
        book.record(.keep, for: item("c", date: day(2024, 6, 1)))
        #expect(book.reviewedCount(in: MonthKey(day(2024, 5, 10))) == 2)
    }

    @Test func streakCountsConsecutiveDaysThroughYesterday() {
        var book = DecisionBook()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        for offset in [1, 2, 3, 5] {
            book.record(.keep, for: item("d\(offset)"), at: cal.date(byAdding: .day, value: -offset, to: today)!)
        }
        #expect(book.streak(endingOn: today) == 3)
        book.record(.keep, for: item("today"), at: today.addingTimeInterval(3600))
        #expect(book.streak(endingOn: today) == 4)
        #expect(book.reviewedCount(on: today) == 1)
    }

    @Test func streakIsZeroAfterAMissedDay() {
        var book = DecisionBook()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        book.record(.keep, for: item("old"), at: cal.date(byAdding: .day, value: -2, to: today)!)
        #expect(book.streak(endingOn: today) == 0)
    }

    @Test func decodesBooksWrittenBeforeActivityExisted() throws {
        let legacy = #"{"records":{},"applied":[]}"#.data(using: .utf8)!
        let book = try JSONDecoder().decode(DecisionBook.self, from: legacy)
        #expect(book.activity.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var book = DecisionBook()
        book.record(.trash, for: item("a", date: day(2024, 5, 1)))
        let data = try JSONEncoder().encode(book)
        #expect(try JSONDecoder().decode(DecisionBook.self, from: data) == book)
    }
}
