import Foundation
import Testing
@testable import Pictr

@Suite struct BlurScorerTests {
    private func image(_ pixel: (Int, Int) -> UInt8, size: Int = 32) -> [UInt8] {
        (0..<size).flatMap { y in (0..<size).map { x in pixel(x, y) } }
    }

    @Test func flatImageHasZeroVariance() {
        let flat = image { _, _ in 128 }
        #expect(BlurScorer.laplacianVariance(gray: flat, width: 32, height: 32) == 0)
    }

    @Test func sharpEdgesScoreHigherThanSoftGradient() {
        let checker = image { x, y in (x / 2 + y / 2) % 2 == 0 ? 0 : 255 }
        let gradient = image { x, _ in UInt8(x * 8) }
        let sharp = BlurScorer.laplacianVariance(gray: checker, width: 32, height: 32)!
        let soft = BlurScorer.laplacianVariance(gray: gradient, width: 32, height: 32)!
        #expect(sharp > 1000)
        #expect(soft < BlurSensitivity.low.threshold)
    }

    @Test func tooSmallReturnsNil() {
        #expect(BlurScorer.laplacianVariance(gray: [1, 2, 3, 4], width: 2, height: 2) == nil)
    }
}

@Suite struct SimilarGrouperTests {
    private func c(_ id: String, _ seconds: TimeInterval) -> SimilarGrouper.Candidate {
        .init(id: id, date: Date(timeIntervalSince1970: seconds))
    }

    @Test func groupsCloseShotsUnderThreshold() {
        let near: Set<Set<String>> = [["a", "b"], ["b", "c"]]
        let groups = SimilarGrouper.groups([c("c", 20), c("a", 0), c("b", 10), c("d", 30)]) { l, r in
            near.contains([l, r]) ? 0.1 : 0.9
        }
        #expect(groups == [["a", "b", "c"]])
    }

    @Test func ignoresShotsOutsideTheWindow() {
        let groups = SimilarGrouper.groups([c("a", 0), c("b", 3600)]) { _, _ in 0.0 }
        #expect(groups.isEmpty)
    }

    @Test func missingDistanceNeverGroups() {
        #expect(SimilarGrouper.groups([c("a", 0), c("b", 1)]) { _, _ in nil }.isEmpty)
    }

    @Test func keeperIsBestScoreThenResolution() {
        let scores: [String: Float] = ["a": 0.2, "b": 0.6, "c": 0.6]
        let pixels = ["a": 10, "b": 10, "c": 20]
        let keepers = SimilarGrouper.keepers(in: ["a", "b", "c"], isFavorite: { _ in false },
                                             score: { scores[$0] }, pixels: { pixels[$0]! })
        #expect(keepers == ["c"])
    }

    @Test func favoritesAreAlwaysTheKeepers() {
        let keepers = SimilarGrouper.keepers(in: ["a", "b", "c"], isFavorite: { $0 != "b" },
                                             score: { $0 == "b" ? 1 : -1 }, pixels: { _ in 1 })
        #expect(keepers == ["a", "c"])
    }
}

@Suite struct AnalysisBucketTests {
    private func photo(_ id: String, favorite: Bool = false, pixels: Int = 100) -> ScannedAsset {
        scanned(FakeAsset(id: id, isFavorite: favorite, pixelWidth: pixels, pixelHeight: 1))
    }

    @Test func similarSuggestsOnlyNonKeepers() {
        let set = Bucketer.buckets(
            for: [photo("a"), photo("b"), photo("c")],
            analysis: ["a": .init(aestheticScore: 0.1, isUtility: false), "b": .init(aestheticScore: 0.8, isUtility: false),
                       "c": .init(aestheticScore: 0.3, isUtility: false)],
            similar: [["a", "b", "c"]]
        )
        #expect(Set(set[.similar].members.map(\.id)) == ["a", "c"])
        #expect(set.similarGroups.first?.keeperIDs == ["b"])
    }

    @Test func favoriteInGroupIsKeptAndNeverSuggested() {
        let set = Bucketer.buckets(
            for: [photo("fav", favorite: true), photo("b")],
            analysis: ["b": .init(aestheticScore: 0.9, isUtility: false)],
            similar: [["fav", "b"]]
        )
        #expect(set[.similar].members.map(\.id) == ["b"])
        #expect(set.similarGroups.first?.keeperIDs == ["fav"])
    }

    @Test func blurrySensitivityMovesTheLine() {
        let assets = [photo("soft"), photo("sharp")]
        let analysis: [String: AssetAnalysis] = [
            "soft": .init(aestheticScore: 0, isUtility: false, sharpness: 60),
            "sharp": .init(aestheticScore: 0, isUtility: false, sharpness: 500),
        ]
        var settings = BucketSettings()
        settings.blur = .low
        #expect(Bucketer.buckets(for: assets, analysis: analysis, settings: settings)[.blurry].members.isEmpty)
        settings.blur = .medium
        #expect(Bucketer.buckets(for: assets, analysis: analysis, settings: settings)[.blurry].members.map(\.id) == ["soft"])
    }

    @Test func smoothWellRatedPhotoIsNotBlurry() {
        let set = Bucketer.buckets(
            for: [photo("sky"), photo("blur")],
            analysis: [
                "sky": .init(aestheticScore: 0.76, isUtility: false, sharpness: 30),
                "blur": .init(aestheticScore: -0.25, isUtility: false, sharpness: 13),
            ]
        )
        #expect(set[.blurry].members.map(\.id) == ["blur"])
    }

    @Test func lowQualityExcludesUtilityAndBlurry() {
        let set = Bucketer.buckets(
            for: [photo("poor"), photo("receipt"), photo("blurPoor"), photo("fine")],
            analysis: [
                "poor": .init(aestheticScore: -0.8, isUtility: false, sharpness: 300),
                "receipt": .init(aestheticScore: -0.8, isUtility: true, sharpness: 300),
                "blurPoor": .init(aestheticScore: -0.8, isUtility: false, sharpness: 10),
                "fine": .init(aestheticScore: 0.5, isUtility: false, sharpness: 300),
            ]
        )
        #expect(set[.lowQuality].members.map(\.id) == ["poor"])
        #expect(set[.utility].members.map(\.id) == ["receipt"])
        #expect(set[.blurry].members.map(\.id) == ["blurPoor"])
    }

    @Test func screenRecordingsAndVideoThresholdSetting() {
        var settings = BucketSettings()
        settings.largeVideoBytes = 50
        let set = Bucketer.buckets(for: [
            scanned(FakeAsset(id: "rec", mediaKind: .video, isScreenRecording: true), bytes: 10),
            scanned(FakeAsset(id: "clip", mediaKind: .video), bytes: 60),
        ], settings: settings)
        #expect(set[.screenRecordings].members.map(\.id) == ["rec"])
        #expect(set[.largeVideos].members.map(\.id) == ["clip"])
    }

    @Test func excludingDecidedDropsEmptyGroupsButKeepsKeepers() {
        let set = Bucketer.buckets(
            for: [photo("a"), photo("b")],
            analysis: ["a": .init(aestheticScore: 0.9, isUtility: false)],
            similar: [["a", "b"]]
        ).excluding(["b"])
        #expect(set.similarGroups.isEmpty)
    }
}
