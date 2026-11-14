import Foundation
@testable import Pictr

struct FakeAsset: AssetDescriptor {
    var id: String
    var creationDate: Date? = Date(timeIntervalSince1970: 1_000_000)
    var mediaKind: AssetMediaKind = .image
    var isScreenshot = false
    var isScreenRecording = false
    var isLivePhoto = false
    var isFavorite = false
    var isHidden = false
    var burstIdentifier: String?
    var isBurstPick = false
    var representsBurst = false
    var pixelWidth = 4032
    var pixelHeight = 3024
    var duration: TimeInterval = 0
    var uniformTypeIdentifier: String? = "public.heic"
    var resources: [ResourceRecord] = []
}

func scanned(_ asset: FakeAsset, bytes: Int64 = 1_000, estimated: Bool = false) -> ScannedAsset {
    ScannedAsset(descriptor: asset, size: AssetSize(bytes: bytes, isEstimated: estimated))
}

func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
