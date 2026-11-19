import Foundation
import Testing
@testable import Pictr

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func year(_ y: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: 6, day: 1))!
}

private let local = [ResourceRecord(kind: .photo, byteCount: 1, isLocallyAvailable: true)]
private let cloud = [ResourceRecord(kind: .video, byteCount: 1, isLocallyAvailable: false)]

private let library: [ScannedAsset] = [
    scanned(FakeAsset(id: "photo", creationDate: year(2024), resources: local), bytes: 100),
    scanned(FakeAsset(id: "live", creationDate: year(2024), isLivePhoto: true), bytes: 300),
    scanned(FakeAsset(id: "clip", creationDate: year(2025), mediaKind: .video, resources: cloud), bytes: 1_000, estimated: true),
    scanned(FakeAsset(id: "shot", creationDate: year(2025), isScreenshot: true), bytes: 50),
    scanned(FakeAsset(id: "recording", creationDate: nil, mediaKind: .video, isScreenRecording: true), bytes: 500),
]

@Suite struct InsightsTests {
    private let insights = LibraryInsights.make(from: library, top: 3, calendar: utc)

    @Test func totalsAreTheSumOfEveryItem() {
        #expect(insights.count == 5)
        #expect(insights.bytes == 1_950)
        #expect(insights.hasEstimates)
    }

    @Test func kindsPartitionTheLibraryLargestFirst() {
        #expect(insights.kinds.map(\.kind) == [.videos, .screenRecordings, .livePhotos, .photos, .screenshots])
        #expect(insights.kinds.map(\.bytes) == [1_000, 500, 300, 100, 50])
        #expect(insights.kinds.reduce(0) { $0 + $1.count } == insights.count)
        #expect(insights.kinds.reduce(0) { $0 + $1.bytes } == insights.bytes)
        #expect(insights.kinds.filter(\.hasEstimates).map(\.kind) == [.videos])
    }

    @Test func yearsOldestFirstWithUndatedApart() {
        #expect(insights.years.map(\.year) == [2024, 2025])
        #expect(insights.years.map(\.bytes) == [400, 1_050])
        #expect(insights.years.map(\.count) == [2, 2])
        #expect(insights.undatedBytes == 500)
        #expect(insights.years.map(\.hasEstimates) == [false, true])
        #expect(insights.years.reduce(0) { $0 + $1.bytes } + insights.undatedBytes == insights.bytes)
    }

    @Test func largestAreOrderedAndCapped() {
        #expect(insights.largest.map(\.id) == ["clip", "recording", "live"])
        #expect(insights.largest.first?.isEstimated == true)
    }

    @Test func storageSplitAddsUp() {
        #expect(insights.onDeviceBytes == 100)
        #expect(insights.cloudOnlyBytes == 1_000)
        #expect(insights.unknownBytes == 850)
        #expect(insights.onDeviceBytes + insights.cloudOnlyBytes + insights.unknownBytes == insights.bytes)
    }

    @Test func emptyLibraryIsEmpty() {
        let empty = LibraryInsights.make(from: [], calendar: utc)
        #expect(empty.count == 0 && empty.bytes == 0)
        #expect(empty.kinds.isEmpty && empty.years.isEmpty && empty.largest.isEmpty)
    }
}
