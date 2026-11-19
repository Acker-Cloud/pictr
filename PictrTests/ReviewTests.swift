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
        #expect(undone == [.init(item: item("b"), decision: .trash)])
        #expect(session.current?.id == "b")
    }

    @Test func batchDecidesAsOneActionAndUndoesWhole() {
        var session = ReviewSession(items: [item("a"), item("b"), item("c"), item("d")])
        session.decide(.keep)
        let steps = session.decide(batch: [.trash, .keep])
        #expect(steps.map(\.item.id) == ["b", "c"])
        #expect(session.current?.id == "d")
        #expect(session.keptCount == 2 && session.trashedCount == 1)

        let undone = session.undo()
        #expect(undone.map(\.item.id) == ["b", "c"])
        #expect(undone.map(\.decision) == [.trash, .keep])
        #expect(session.current?.id == "b")
        #expect(session.undo().map(\.item.id) == ["a"])
        #expect(!session.canUndo)
        #expect(session.undo().isEmpty)
    }

    @Test func batchStopsAtTheEndOfTheDeck() {
        var session = ReviewSession(items: [item("a"), item("b")])
        session.decide(.keep)
        #expect(session.decide(batch: [.trash, .trash, .trash]).map(\.item.id) == ["b"])
        #expect(session.isFinished)
        #expect(session.undo().count == 1)
        #expect(session.current?.id == "b")
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

@Suite struct MomentTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ id: String, _ seconds: TimeInterval?) -> ReviewItem {
        item(id, date: seconds.map { t0.addingTimeInterval($0) })
    }

    @Test func groupsShotsTakenInQuickSuccession() {
        let items = [at("a", 0), at("b", 30), at("c", 140), at("d", 900), at("e", 905)]
        #expect(Moment.run(in: items, from: 0) == 0..<3)
        #expect(Moment.run(in: items, from: 1) == 1..<3)
        #expect(Moment.run(in: items, from: 3) == 3..<5)
    }

    @Test func gapIsBetweenNeighboursNotFromTheFirstShot() {
        // Each shot 100s after the last: 300s end to end, still one moment.
        let items = [at("a", 0), at("b", 100), at("c", 200), at("d", 300)]
        #expect(Moment.run(in: items, from: 0) == 0..<4)
    }

    @Test func worksInEitherDirection() {
        let items = [at("a", 60), at("b", 30), at("c", 0)]
        #expect(Moment.run(in: items, from: 0) == 0..<3)
    }

    @Test func undatedShotsAndBoundsStandAlone() {
        let items = [at("a", 0), at("b", nil), at("c", 10)]
        #expect(Moment.run(in: items, from: 0) == 0..<1)
        #expect(Moment.run(in: items, from: 1) == 1..<2)
        #expect(Moment.run(in: items, from: 3) == 3..<3)
    }

    @Test func capsLongBursts() {
        let items = (0..<10).map { at("\($0)", TimeInterval($0)) }
        #expect(Moment.run(in: items, from: 0, maxCount: 4) == 0..<4)
        #expect(Moment.run(in: items, from: 4, maxCount: 4) == 4..<8)
    }
}
