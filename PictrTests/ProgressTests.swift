import Foundation
import Testing
@testable import Pictr

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

private func item(_ id: String, favorite: Bool = false) -> ReviewItem {
    ReviewItem(id: id, creationDate: day(2020, 1, 1), mediaKind: .image, duration: 0,
               isFavorite: favorite, pixelWidth: 1, pixelHeight: 1)
}

@Suite struct ProgressStatsTests {
    @Test func totalsCountEveryDecisionAndApply() {
        var book = DecisionBook()
        book.record(.keep, for: item("a"), at: day(2026, 11, 1))
        book.record(.trash, for: item("b"), at: day(2026, 11, 1))
        book.record(.trash, for: item("c"), at: day(2026, 11, 2))
        book.finishApply(queued: ["b"], submitted: ["b"], bytes: 2_000, at: day(2026, 11, 3))
        let stats = book.stats(calendar: utc, on: day(2026, 11, 3))
        #expect(stats.reviewed == 3)
        #expect(stats.kept == 1)
        #expect(stats.queued == 1)
        #expect(stats.movedCount == 1)
        #expect(stats.movedBytes == 2_000)
        #expect(stats.cleanups == 1)
    }

    @Test func reviewedNeverTrailsKeptForOlderData() throws {
        // Decisions saved before the activity log existed.
        let json = #"{"records":{"a":{"decision":"keep","decidedAt":0},"b":{"decision":"keep","decidedAt":0}},"applied":[]}"#
        let book = try JSONDecoder().decode(DecisionBook.self, from: Data(json.utf8))
        let stats = book.stats(calendar: utc, on: day(2026, 11, 3))
        #expect(stats.kept == 2)
        #expect(stats.reviewed == 2)
    }

    @Test func bestStreakFindsLongestRun() {
        var book = DecisionBook()
        for d in [1, 2, 3, 4, 7, 8, 10] {
            book.record(.keep, for: item("x\(d)"), at: day(2026, 11, d))
        }
        #expect(book.bestStreak(calendar: utc) == 4)
        #expect(DecisionBook().bestStreak(calendar: utc) == 0)
    }

    @Test func recentDaysIncludesZeros() {
        var book = DecisionBook()
        book.record(.keep, for: item("a"), at: day(2026, 11, 12))
        book.record(.keep, for: item("b"), at: day(2026, 11, 14))
        book.record(.keep, for: item("c"), at: day(2026, 11, 14))
        let days = book.recentDays(3, endingOn: day(2026, 11, 14), calendar: utc)
        #expect(days.map(\.count) == [1, 0, 2])
        #expect(days.last?.date == utc.startOfDay(for: day(2026, 11, 14)))
    }
}

@Suite struct CleanupPlanTests {
    @Test func progressCountsOnlyAppliesSinceStart() {
        var book = DecisionBook()
        book.finishApply(queued: [], submitted: ["old"], bytes: 900, at: day(2026, 11, 1))
        book.startPlan(targetBytes: 1_000, at: day(2026, 11, 2))
        book.finishApply(queued: [], submitted: ["a"], bytes: 300, at: day(2026, 11, 3))
        book.finishApply(queued: [], submitted: ["b"], bytes: 400, at: day(2026, 11, 4))
        #expect(book.planProgress == 700)
        #expect(book.plan?.targetBytes == 1_000)
        book.endPlan()
        #expect(book.plan == nil)
        #expect(book.planProgress == 0)
    }

    @Test func oldBooksDecodeWithoutPlan() throws {
        let json = #"{"records":{},"applied":[]}"#
        let book = try JSONDecoder().decode(DecisionBook.self, from: Data(json.utf8))
        #expect(book.plan == nil)
    }

    @Test func planSurvivesEncoding() throws {
        var book = DecisionBook()
        book.startPlan(targetBytes: 500_000_000, at: day(2026, 11, 2))
        let decoded = try JSONDecoder().decode(DecisionBook.self, from: JSONEncoder().encode(book))
        #expect(decoded.plan == book.plan)
    }
}

@Suite struct AchievementTests {
    @Test func unlocksByThreshold() {
        let stats = ProgressStats(reviewed: 120, kept: 100, queued: 0, movedCount: 20, movedBytes: 2_000_000_000,
                                  cleanups: 1, streak: 2, bestStreak: 8, tasteAnswers: 0)
        let unlocked = Set(Achievement.allCases.filter { $0.progress(stats).unlocked })
        #expect(unlocked.contains(.firstSwipe))
        #expect(unlocked.contains(.reviewed100))
        #expect(!unlocked.contains(.reviewed1000))
        #expect(unlocked.contains(.streak7))
        #expect(!unlocked.contains(.streak30))
        #expect(unlocked.contains(.firstCleanup))
        #expect(unlocked.contains(.moved1GB))
        #expect(!unlocked.contains(.tasteTrained))
    }

    @Test func lockedShowsProgress() {
        let stats = ProgressStats(reviewed: 37, kept: 0, queued: 0, movedCount: 0, movedBytes: 0,
                                  cleanups: 0, streak: 0, bestStreak: 0, tasteAnswers: 0)
        let progress = Achievement.reviewed100.progress(stats)
        #expect(!progress.unlocked)
        #expect(progress.fraction == 0.37)
        #expect(progress.label == "37 of 100")
    }
}
