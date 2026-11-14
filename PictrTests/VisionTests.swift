import CoreGraphics
import Foundation
import ImageIO
import Testing
import Vision
@testable import Pictr

private final class FixtureAnchor {}

private var isSimulator: Bool {
    #if targetEnvironment(simulator)
    true
    #else
    false
    #endif
}

/// Vision's models do not run in the simulator ("Failed to create espresso
/// context"), so these run on a device only:
/// `xcodebuild ... -destination 'platform=iOS,name=<iPhone>' -only-testing:PictrTests/VisionTests test`
@Suite(.enabled(if: !isSimulator, "Vision models need a device"))
struct VisionTests {
    private func analyze(_ name: String) async throws -> VisionAnalyzer.Output {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "jpg"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return await VisionAnalyzer().analyze(image)
    }

    /// Measured on an iPhone: the drawn moon-over-mountains fixtures tag as outdoor,
    /// celestial_body, moon (0.15 to 0.33); the abstract blur fixture gets nothing
    /// above the floor, which is right for an image with no subject.
    @Test func classifierTagsScenesAndSkipsAbstractBlur() async throws {
        for name in ["seed-0", "similar-a", "blurry"] {
            let output = try await analyze(name)
            print("tags \(name):", output.tags.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key)=\(String(format: "%.2f", $0.value))" })
            if name != "blurry" { #expect(output.tags["moon"] != nil) }
            #expect(output.tags.count <= VisionAnalyzer.maxTags)
            #expect(output.tags.values.allSatisfy { $0 >= VisionAnalyzer.tagFloor })
            #expect(output.print != nil)
        }
    }

    @Test func nearDuplicatesFallUnderThresholdAndOthersDoNot() async throws {
        let a = try #require(await analyze("similar-a").print)
        let b = try #require(await analyze("similar-b").print)
        let c = try #require(await analyze("similar-c").print)
        let other = try #require(await analyze("blurry").print)
        let unrelated = try #require(await analyze("seed-0").print)
        #expect(try a.distance(to: b) < SimilarGrouper.threshold)
        #expect(try a.distance(to: c) < SimilarGrouper.threshold)
        #expect(try a.distance(to: other) > SimilarGrouper.threshold)
        #expect(try a.distance(to: unrelated) > SimilarGrouper.threshold)
    }

    @Test func blurryFixtureLandsInBlurryAndSmoothOneDoesNot() async throws {
        let blurry = try await analyze("blurry").analysis
        let smooth = try await analyze("seed-0").analysis
        let set = Bucketer.buckets(
            for: [scanned(FakeAsset(id: "blurry")), scanned(FakeAsset(id: "smooth"))],
            analysis: ["blurry": blurry, "smooth": smooth]
        )
        #expect(set[.blurry].members.map(\.id) == ["blurry"])
    }
}
