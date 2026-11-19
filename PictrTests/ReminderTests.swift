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

@Suite struct ReminderPlanTests {
    @Test func schedulesOnlyDaysWithPhotos() {
        // Photos exist only on Nov 15 and Nov 17 in earlier years.
        let plan = ReminderPlan.entries(from: day(2026, 11, 14), days: 5, hour: 9, minute: 30,
                                        earliestYear: 2020, calendar: utc) { windows in
            let parts = utc.dateComponents([.month, .day], from: windows[0].start)
            switch (parts.month, parts.day) {
            case (11, 15): return 4
            case (11, 17): return 1
            default: return 0
            }
        }
        #expect(plan.map(\.fireDate.day) == [15, 17])
        #expect(plan.allSatisfy { $0.fireDate.hour == 9 && $0.fireDate.minute == 30 && $0.fireDate.year == 2026 })
        #expect(plan.map(\.photoCount) == [4, 1])
    }

    @Test func startsTomorrowNotToday() {
        let plan = ReminderPlan.entries(from: day(2026, 11, 14), days: 2, hour: 9, minute: 0,
                                        earliestYear: 2020, calendar: utc) { _ in 3 }
        #expect(plan.map(\.fireDate.day) == [15, 16])
    }

    @Test func windowsCoverEveryEarlierYear() {
        var seen: [Int] = []
        _ = ReminderPlan.entries(from: day(2026, 11, 14), days: 1, hour: 9, minute: 0,
                                 earliestYear: 2023, calendar: utc) { windows in
            seen = windows.map { utc.component(.year, from: $0.start) }
            return 1
        }
        #expect(seen == [2025, 2024, 2023])
    }

    @Test func bodyCountsPhotos() {
        #expect(ReminderPlan.body(photoCount: 1) == "1 photo from this day in past years is waiting.")
        #expect(ReminderPlan.body(photoCount: 12) == "12 photos from this day in past years are waiting.")
        #expect(ReminderPlan.body(photoCount: 3, range: .week) == "3 photos from this week in past years are waiting.")
    }

    @Test func weekRangeCountsTheWholeWeek() {
        var seen: [DateInterval] = []
        _ = ReminderPlan.entries(from: day(2026, 11, 14), days: 1, hour: 9, minute: 0,
                                 earliestYear: 2025, range: .week, calendar: utc) { windows in
            seen = windows
            return 1
        }
        #expect(seen == [DateInterval(start: day(2025, 11, 12), duration: 7 * 86_400)])
    }
}
