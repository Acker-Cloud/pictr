import Foundation
import Testing
@testable import Pictr

@Suite struct BucketerTests {
    private func ids(_ bucket: Bucket) -> Set<String> { Set(bucket.members.map(\.id)) }

    @Test func screenshotsAreBucketed() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "shot", isScreenshot: true)),
            scanned(FakeAsset(id: "photo")),
        ])
        #expect(ids(set[.screenshots]) == ["shot"])
    }

    @Test func favoritesAndHiddenAreExcludedEverywhere() {
        let threshold = Bucketer.largeVideoThreshold
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "favShot", isScreenshot: true, isFavorite: true)),
            scanned(FakeAsset(id: "hiddenShot", isScreenshot: true, isHidden: true)),
            scanned(FakeAsset(id: "favVideo", mediaKind: .video, isFavorite: true), bytes: threshold * 2),
            scanned(FakeAsset(id: "hiddenVideo", mediaKind: .video, isHidden: true), bytes: threshold * 2),
            scanned(FakeAsset(id: "b1", burstIdentifier: "B", isBurstPick: true)),
            scanned(FakeAsset(id: "b2", isFavorite: true, burstIdentifier: "B")),
            scanned(FakeAsset(id: "b3", isHidden: true, burstIdentifier: "B")),
        ])
        #expect(set.uniqueMembers.isEmpty)
    }

    @Test func burstKeepsPicksAndSuggestsTheRest() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "b1", creationDate: date(1), burstIdentifier: "B")),
            scanned(FakeAsset(id: "b2", creationDate: date(2), burstIdentifier: "B", isBurstPick: true)),
            scanned(FakeAsset(id: "b3", creationDate: date(3), burstIdentifier: "B")),
            scanned(FakeAsset(id: "b4", creationDate: date(4), burstIdentifier: "B", isBurstPick: true)),
        ])
        #expect(ids(set[.burstExtras]) == ["b1", "b3"])
    }

    @Test func burstWithoutPickKeepsFirstFrame() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "late", creationDate: date(30), burstIdentifier: "B")),
            scanned(FakeAsset(id: "first", creationDate: date(10), burstIdentifier: "B")),
            scanned(FakeAsset(id: "mid", creationDate: date(20), burstIdentifier: "B")),
        ])
        #expect(ids(set[.burstExtras]) == ["late", "mid"])
    }

    @Test func burstRepresentativeIsAlwaysKept() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "b1", creationDate: date(1), burstIdentifier: "B")),
            scanned(FakeAsset(id: "cover", creationDate: date(2), burstIdentifier: "B", representsBurst: true)),
            scanned(FakeAsset(id: "auto", creationDate: date(3), burstIdentifier: "B", isBurstPick: true)),
        ])
        #expect(ids(set[.burstExtras]) == ["b1"])
    }

    @Test func burstWithoutPickPrefersRepresentativeOverFirstFrame() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "first", creationDate: date(1), burstIdentifier: "B")),
            scanned(FakeAsset(id: "cover", creationDate: date(2), burstIdentifier: "B", representsBurst: true)),
            scanned(FakeAsset(id: "last", creationDate: date(3), burstIdentifier: "B")),
        ])
        #expect(ids(set[.burstExtras]) == ["first", "last"])
    }

    @Test func burstsAreGroupedIndependently() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "a1", creationDate: date(1), burstIdentifier: "A")),
            scanned(FakeAsset(id: "a2", creationDate: date(2), burstIdentifier: "A")),
            scanned(FakeAsset(id: "c1", creationDate: date(1), burstIdentifier: "C", isBurstPick: true)),
            scanned(FakeAsset(id: "c2", creationDate: date(2), burstIdentifier: "C")),
        ])
        #expect(ids(set[.burstExtras]) == ["a2", "c2"])
    }

    @Test func singleFrameBurstSuggestsNothing() {
        let set = Bucketer.buckets(for: [scanned(FakeAsset(id: "solo", burstIdentifier: "S"))])
        #expect(set[.burstExtras].members.isEmpty)
    }

    @Test func largeVideoThresholdIsInclusiveAndSortedBySize() {
        let threshold = Bucketer.largeVideoThreshold
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "under", mediaKind: .video), bytes: threshold - 1),
            scanned(FakeAsset(id: "at", mediaKind: .video), bytes: threshold),
            scanned(FakeAsset(id: "big", mediaKind: .video), bytes: threshold * 3),
            scanned(FakeAsset(id: "hugePhoto", mediaKind: .image), bytes: threshold * 5),
        ])
        #expect(set[.largeVideos].members.map(\.id) == ["big", "at"])
    }

    @Test func totalsEqualSumOfMembers() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "s1", isScreenshot: true), bytes: 1_200),
            scanned(FakeAsset(id: "s2", isScreenshot: true), bytes: 3_400, estimated: true),
            scanned(FakeAsset(id: "v1", mediaKind: .video), bytes: 150_000_000),
        ])
        for bucket in set.buckets {
            #expect(bucket.totalBytes == bucket.members.reduce(0) { $0 + $1.size.bytes })
        }
        #expect(set[.screenshots].totalBytes == 4_600)
        #expect(set[.screenshots].hasEstimates)
        #expect(!set[.largeVideos].hasEstimates)
        #expect(set.reclaimableBytes == 150_004_600)
        #expect(set.reclaimableHasEstimates)
    }

    @Test func cloudOnlyBytesUseResourceAvailability() {
        let cloud = FakeAsset(id: "cloud", isScreenshot: true, resources: [
            ResourceRecord(kind: .photo, byteCount: 10, isLocallyAvailable: false),
        ])
        let local = FakeAsset(id: "local", isScreenshot: true, resources: [
            ResourceRecord(kind: .photo, byteCount: 10, isLocallyAvailable: true),
        ])
        let set = Bucketer.buckets(for: [scanned(cloud, bytes: 500), scanned(local, bytes: 700)])
        #expect(set.cloudOnlyBytes == 500)
        #expect(set[.screenshots].members.first { $0.id == "local" }?.availability == .onDevice)
    }

    @Test func emptyInputYieldsThreeEmptyBuckets() {
        let set = Bucketer.buckets(for: [])
        #expect(set.buckets.map(\.kind) == BucketKind.allCases)
        #expect(set.reclaimableBytes == 0)
    }
}

@Suite struct BucketSetExclusionTests {
    @Test func excludingDropsDecidedMembers() {
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "s1", isScreenshot: true)),
            scanned(FakeAsset(id: "s2", isScreenshot: true)),
        ]).excluding(["s1"])
        #expect(set[.screenshots].members.map(\.id) == ["s2"])
    }
}
