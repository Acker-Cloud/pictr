import Foundation
import Testing
@testable import Pictr

@Suite struct SizeProviderTests {
    @Test func resourceProviderSumsEveryResource() {
        let asset = FakeAsset(id: "live", isLivePhoto: true, resources: [
            ResourceRecord(kind: .photo, byteCount: 2_000_000),
            ResourceRecord(kind: .pairedVideo, byteCount: 3_000_000),
            ResourceRecord(kind: .fullSizePhoto, byteCount: 2_500_000),
        ])
        #expect(ResourceSizeProvider().size(of: asset) == AssetSize(bytes: 7_500_000, isEstimated: false))
    }

    @Test func resourceProviderReturnsNilWhenAnySizeIsMissing() {
        let asset = FakeAsset(id: "x", resources: [
            ResourceRecord(kind: .photo, byteCount: 2_000_000),
            ResourceRecord(kind: .pairedVideo, byteCount: nil),
        ])
        #expect(ResourceSizeProvider().size(of: asset) == nil)
        #expect(ResourceSizeProvider().size(of: FakeAsset(id: "none")) == nil)
    }

    @Test func estimatesPhotoFromPixelsAndType() {
        let heic = FakeAsset(id: "h", pixelWidth: 4000, pixelHeight: 3000, uniformTypeIdentifier: "public.heic")
        let png = FakeAsset(id: "p", pixelWidth: 1000, pixelHeight: 2000, uniformTypeIdentifier: "public.png")
        let jpeg = FakeAsset(id: "j", pixelWidth: 4000, pixelHeight: 3000, uniformTypeIdentifier: "public.jpeg")
        let provider = EstimatedSizeProvider()
        #expect(provider.size(of: heic) == AssetSize(bytes: 3_000_000, isEstimated: true))
        #expect(provider.size(of: png) == AssetSize(bytes: 3_000_000, isEstimated: true))
        #expect(provider.size(of: jpeg) == AssetSize(bytes: 6_000_000, isEstimated: true))
    }

    @Test func estimatesLivePhotoIncludesPairedVideo() {
        let still = FakeAsset(id: "s", pixelWidth: 4000, pixelHeight: 3000)
        var live = still
        live.isLivePhoto = true
        let provider = EstimatedSizeProvider()
        let delta = provider.size(of: live)!.bytes - provider.size(of: still)!.bytes
        #expect(delta == Int64(EstimatedSizeProvider.livePhotoVideoSeconds * EstimatedSizeProvider.videoBytesPerSecond))
    }

    @Test func estimatesVideoFromDuration() {
        let video = FakeAsset(id: "v", mediaKind: .video, duration: 60)
        let expected = Int64(60 * EstimatedSizeProvider.videoBytesPerSecond)
        #expect(EstimatedSizeProvider().size(of: video) == AssetSize(bytes: expected, isEstimated: true))
    }

    @Test func unknownMediaHasNoEstimate() {
        #expect(EstimatedSizeProvider().size(of: FakeAsset(id: "o", mediaKind: .other)) == nil)
    }

    @Test func fallbackPrefersExactThenEstimates() {
        let provider: some SizeProvider = .standard
        let exact = FakeAsset(id: "e", resources: [ResourceRecord(kind: .photo, byteCount: 42)])
        let unknown = FakeAsset(id: "u", pixelWidth: 100, pixelHeight: 100, resources: [
            ResourceRecord(kind: .photo, byteCount: nil),
        ])
        #expect(provider.size(of: exact) == AssetSize(bytes: 42, isEstimated: false))
        #expect(provider.size(of: unknown) == AssetSize(bytes: 2_500, isEstimated: true))
    }
}
