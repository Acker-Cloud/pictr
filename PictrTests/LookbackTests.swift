import Foundation
import Testing
@testable import Pictr

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2 // Monday
    return calendar
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

/// Newest first, as the library returns them.
private let index: [AssetStamp] = [
    AssetStamp(id: "a", date: at(2026, 11, 14, 18)),
    AssetStamp(id: "b", date: at(2026, 11, 14, 9)),
    AssetStamp(id: "c", date: at(2026, 11, 10)),   // Same Monday-start week as Saturday Nov 14.
    AssetStamp(id: "d", date: at(2026, 10, 2)),
    AssetStamp(id: "e", date: at(2025, 3, 1)),
]

@Suite struct LookbackGroupingTests {
    private func entries(_ unit: PeriodUnit, sort: LookbackSort = .newest, decided: Set<String> = [],
                         hideDone: Bool = false) -> [PeriodEntry] {
        let groups = PeriodGrouping.group(index, by: unit, calendar: utc)
        return PeriodGrouping.entries(groups, decided: decided, sort: sort, hideDone: hideDone)
    }

    @Test func groupsByEachUnit() {
        #expect(entries(.day).map(\.count) == [2, 1, 1, 1])
        #expect(entries(.week).map(\.count) == [3, 1, 1])
        #expect(entries(.month).map(\.count) == [3, 1, 1])
        #expect(entries(.year).map(\.count) == [4, 1])
    }

    @Test func coverCandidatesAreNewestFirst() {
        let day = entries(.day).first
        #expect(day?.coverIDs == ["a", "b"])
        #expect(entries(.year).first?.coverIDs == ["a", "b", "c", "d"])
    }

    @Test func reviewedCountsDecidedPhotosInThePeriod() {
        let months = entries(.month, decided: ["a", "c", "e"])
        #expect(months.map(\.reviewed) == [2, 0, 1])
        #expect(months.last?.isDone == true)
        #expect(entries(.month, decided: ["e"], hideDone: true).map(\.count) == [3, 1])
    }

    @Test func sortsByCountAndWhatsLeft() {
        #expect(entries(.month, sort: .oldest).map(\.count) == [1, 1, 3])
        #expect(entries(.month, sort: .mostPhotos).first?.count == 3)
        #expect(entries(.month, sort: .mostLeft, decided: ["a", "b", "c"]).map(\.left) == [1, 1, 0])
    }

    @Test func sectionsByYearExceptForYearsAndRankedSorts() {
        let byYear = PeriodGrouping.sections(entries(.month), unit: .month, sort: .newest)
        #expect(byYear.map(\.year) == [2026, 2025])
        #expect(PeriodGrouping.sections(entries(.year), unit: .year, sort: .newest).map(\.year) == [nil])
        #expect(PeriodGrouping.sections(entries(.month, sort: .mostLeft), unit: .month, sort: .mostLeft).map(\.year) == [nil])
    }

    @Test func titlesReadNaturally() throws {
        let key = PeriodKey(unit: .week, start: at(2026, 11, 9, 0))
        #expect(PeriodKey(unit: .year, start: at(2026, 1, 1, 0)).title(calendar: utc) == "2026")
        #expect(key.title(calendar: utc).hasPrefix("Week of"))
        #expect(PeriodKey(unit: .month, start: at(2026, 11, 1, 0)).title(calendar: utc).contains("2026"))
        let week = try #require(key.interval(calendar: utc))
        #expect(week.start == at(2026, 11, 9, 0))
        #expect(week.end == at(2026, 11, 16, 0))
    }
}

@Suite struct AssetIndexCacheTests {
    @Test func roundTrips() {
        let url = FileManager.default.temporaryDirectory.appending(path: "index-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = AssetIndexCache(fileURL: url)
        #expect(cache.load() == nil)
        cache.save(index)
        #expect(cache.load() == index)
    }

    @Test func corruptFileLoadsAsNil() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "index-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("nope".utf8).write(to: url)
        #expect(AssetIndexCache(fileURL: url).load() == nil)
    }
}
