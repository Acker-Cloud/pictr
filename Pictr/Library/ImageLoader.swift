import AVFoundation
import Photos
import UIKit

/// Carries PhotoKit results that are not Sendable out of their callback queue.
/// Safe here: each value is handed to the main actor once and never shared.
struct Handoff<Value>: @unchecked Sendable {
    let value: Value
}

/// Screen-sized images for the swipe deck. Lets Photos fetch from iCloud for display,
/// since older photos are often not stored full size on the device.
@MainActor
final class ImageLoader {
    private lazy var manager = PHCachingImageManager()
    private var assets: [String: PHAsset] = [:]

    private static func options() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return options
    }

    private func asset(_ id: String) -> PHAsset? {
        if let cached = assets[id] { return cached }
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: PhotoKitClient.idFetchOptions()).firstObject
        assets[id] = asset
        return asset
    }

    func preheat(_ ids: [String], targetSize: CGSize) {
        let found = ids.compactMap(asset)
        manager.startCachingImages(for: found, targetSize: targetSize, contentMode: .aspectFit, options: Self.options())
    }

    /// A streamable player item for a video, fetched from iCloud if needed.
    func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = asset(id) else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let manager = manager
        let handoff = await withCheckedContinuation { (continuation: CheckedContinuation<Handoff<AVPlayerItem?>, Never>) in
            manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: Handoff(value: item))
            }
        }
        return handoff.value
    }

    /// The Live Photo for an asset, final quality only.
    func livePhoto(for id: String, targetSize: CGSize) async -> PHLivePhoto? {
        guard let asset = asset(id) else { return nil }
        let options = PHLivePhotoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let manager = manager
        let handoff = await withCheckedContinuation { (continuation: CheckedContinuation<Handoff<PHLivePhoto?>, Never>) in
            manager.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { photo, _ in
                continuation.resume(returning: Handoff(value: photo))
            }
        }
        return handoff.value
    }

    /// Yields a fast degraded image, then the final one.
    func images(for id: String, targetSize: CGSize) -> AsyncStream<UIImage> {
        guard let asset = asset(id) else { return AsyncStream { $0.finish() } }
        return AsyncStream { continuation in
            let requestID = manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit,
                                                 options: Self.options()) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                if !degraded { continuation.finish() }
            }
            continuation.onTermination = { [manager] _ in manager.cancelImageRequest(requestID) }
        }
    }
}
