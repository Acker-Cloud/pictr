import Foundation
import Testing
@testable import Pictr

private func copy(_ id: String, at seconds: TimeInterval = 1_000_000, bytes: Int64? = 2_000_000,
                  width: Int = 4032, height: Int = 3024, kind: AssetMediaKind = .image, duration: TimeInterval = 0,
                  favorite: Bool = false, hidden: Bool = false, burst: String? = nil, edited: Bool = false) -> ScannedAsset {
    var resources = [ResourceRecord(kind: kind == .video ? .video : .photo, byteCount: bytes, isLocallyAvailable: true)]
    if edited {
        resources.append(ResourceRecord(kind: kind == .video ? .fullSizeVideo : .fullSizePhoto, byteCount: 900,
                                        isLocallyAvailable: true))
    }
    let asset = FakeAsset(id: id, creationDate: date(seconds), mediaKind: kind, isFavorite: favorite, isHidden: hidden,
                          burstIdentifier: burst, pixelWidth: width, pixelHeight: height, duration: duration,
                          resources: resources)
    return scanned(asset, bytes: bytes ?? 0, estimated: bytes == nil)
}

@Suite struct DuplicateTests {
    @Test func groupsExactCopiesAndKeepsTheLowestID() {
        let groups = DuplicateFinder.groups(in: [copy("b"), copy("a"), copy("other", bytes: 1_999_999)])
        #expect(groups == [SimilarGroup(memberIDs: ["a", "b"], keeperIDs: ["a"])])
        #expect(groups.first?.extraIDs == ["b"])
    }

    @Test func captureSecondMattersNotTheFraction() {
        #expect(DuplicateFinder.groups(in: [copy("a", at: 100.1), copy("b", at: 100.8)]).count == 1)
        #expect(DuplicateFinder.groups(in: [copy("a", at: 100.9), copy("b", at: 101.0)]).isEmpty)
    }

    @Test func pixelSizeAndDurationMatter() {
        #expect(DuplicateFinder.groups(in: [copy("a"), copy("b", width: 3024, height: 4032)]).isEmpty)
        #expect(DuplicateFinder.groups(in: [copy("a", kind: .video, duration: 12.0),
                                            copy("b", kind: .video, duration: 12.5)]).isEmpty)
        #expect(DuplicateFinder.groups(in: [copy("a", kind: .video, duration: 12.0),
                                            copy("b", kind: .video, duration: 12.0)]).count == 1)
        #expect(DuplicateFinder.groups(in: [copy("a"), copy("b", kind: .video)]).isEmpty)
    }

    @Test func ignoresBurstsHiddenAndUnknownSizes() {
        #expect(DuplicateFinder.groups(in: [copy("a", burst: "B"), copy("b", burst: "B")]).isEmpty)
        #expect(DuplicateFinder.groups(in: [copy("a"), copy("b", hidden: true)]).isEmpty)
        #expect(DuplicateFinder.groups(in: [copy("a", bytes: nil), copy("b", bytes: nil)]).isEmpty)
        #expect(DuplicateFinder.groups(in: [copy("a", bytes: 0), copy("b", bytes: 0)]).isEmpty)
    }

    @Test func aLivePhotoIsNotACopyOfItsStill() {
        let live = scanned(FakeAsset(id: "a", creationDate: date(1_000_000), isLivePhoto: true,
                                     resources: [ResourceRecord(kind: .photo, byteCount: 2_000_000, isLocallyAvailable: true)]),
                           bytes: 2_000_000)
        #expect(DuplicateFinder.groups(in: [live, copy("b")]).isEmpty)
    }

    @Test func queuedKeeperDropsTheGroupAndItsPreselection() {
        let set = Bucketer.buckets(for: [copy("a"), copy("b"), copy("c")])
        let keeperQueued = set.excluding(["a"], queued: ["a"])
        #expect(keeperQueued.duplicateGroups.isEmpty)
        #expect(keeperQueued[.duplicates].members.isEmpty)
        // A kept keeper still protects its copies.
        let keeperKept = set.excluding(["a"])
        #expect(keeperKept.duplicateGroups.first?.extraIDs == ["b", "c"])
    }

    @Test func similarLeavesExactCopiesToDuplicates() {
        let other = scanned(FakeAsset(id: "z", creationDate: date(1_000_030), resources: [
            ResourceRecord(kind: .photo, byteCount: 3_000_000, isLocallyAvailable: true),
        ]), bytes: 3_000_000)
        let set = Bucketer.buckets(for: [copy("a"), copy("b"), other], similar: [["a", "b", "z"]])
        #expect(set.similarGroups.flatMap(\.memberIDs).contains("a"))
        #expect(!set.similarGroups.flatMap(\.memberIDs).contains("b"))
        #expect(set[.duplicates].members.map(\.id) == ["b"])
    }

    @Test func keeperIsFavoriteThenEditedThenLowestID() {
        let edited = DuplicateFinder.groups(in: [copy("a"), copy("b", edited: true), copy("c")])
        #expect(edited.first?.keeperIDs == ["b"])
        #expect(edited.first?.memberIDs == ["b", "a", "c"])

        let favorite = DuplicateFinder.groups(in: [copy("a"), copy("b", edited: true), copy("c", favorite: true)])
        #expect(favorite.first?.keeperIDs == ["c"])
        #expect(favorite.first?.extraIDs == ["a", "b"])
    }

    @Test func groupsWithNothingToRemoveAreDropped() {
        #expect(DuplicateFinder.groups(in: [copy("a", favorite: true), copy("b", favorite: true)]).isEmpty)
    }

    @Test func bucketHoldsTheExtrasAndSkipsDecided() {
        let set = Bucketer.buckets(for: [copy("a"), copy("b"), copy("c")])
        #expect(set[.duplicates].members.map(\.id) == ["b", "c"])
        #expect(set.duplicateGroups.count == 1)
        #expect(!BucketKind.duplicates.needsAnalysis)

        let decided = set.excluding(["b", "c"])
        #expect(decided[.duplicates].members.isEmpty)
        #expect(decided.duplicateGroups.isEmpty)
    }
}
