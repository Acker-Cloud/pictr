import Photos
import UIKit

struct Thumbnail: Sendable {
    var image: UIImage?
    /// The image could not be produced without downloading from iCloud.
    var isInCloud: Bool
}

/// Local-only thumbnails. Never touches the network.
@MainActor
final class ThumbnailProvider {
    private lazy var manager = PHCachingImageManager()
    private var assets: [String: PHAsset] = [:]
    private let options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        return options
    }()

    func prepare(ids: [String], targetSize: CGSize) {
        let missing = ids.filter { assets[$0] == nil }
        guard !missing.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: missing, options: PhotoKitClient.idFetchOptions())
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        for asset in fetched { assets[asset.localIdentifier] = asset }
        manager.startCachingImages(for: fetched, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }

    func stop() {
        manager.stopCachingImagesForAllAssets()
        assets = [:]
    }

    func thumbnail(for id: String, targetSize: CGSize) async -> Thumbnail {
        guard let asset = assets[id]
            ?? PHAsset.fetchAssets(withLocalIdentifiers: [id], options: PhotoKitClient.idFetchOptions()).firstObject
        else {
            return Thumbnail(image: nil, isInCloud: false)
        }
        assets[id] = asset
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
                let inCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
                continuation.resume(returning: Thumbnail(image: image, isInCloud: inCloud && image == nil))
            }
        }
    }
}
