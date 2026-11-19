import Foundation
import Photos
import UIKit

/// PhotoKit implementation of `PhotoLibraryClient`, and the library change observer.
///
/// `@unchecked Sendable`: the only mutable state (`fetchResult`, `continuation`)
/// is guarded by `lock`. PhotoKit calls `photoLibraryDidChange` on its own queue.
final class PhotoKitClient: NSObject, PhotoLibraryClient, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    let changes: AsyncStream<LibraryDelta>

    private let lock = NSLock()
    private var fetchResult: PHFetchResult<PHAsset>?
    private var isObserving = false
    private let continuation: AsyncStream<LibraryDelta>.Continuation

    override init() {
        (changes, continuation) = AsyncStream.makeStream(of: LibraryDelta.self, bufferingPolicy: .unbounded)
        super.init()
    }

    deinit {
        if isObserving { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
        continuation.finish()
    }

    // MARK: Authorization

    func authorizationState() -> AuthState {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> AuthState {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private static func map(_ status: PHAuthorizationStatus) -> AuthState {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    // MARK: Fetch

    func enumerateAssets(since: Date, _ body: (any AssetDescriptor, Int, Int) -> Void) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", since as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAllBurstAssets = true
        options.includeHiddenAssets = false
        // TODO(shared-library): PhotoKit has no public per-asset signal for iCloud
        // Shared Library membership, so shared-library assets can still appear.
        // `.typeUserLibrary` only excludes Shared Albums and iTunes-synced assets.
        options.includeAssetSourceTypes = [.typeUserLibrary]

        // Register before fetching so no change slips between snapshot and observer.
        lock.lock()
        let needsRegistration = !isObserving
        isObserving = true
        lock.unlock()
        if needsRegistration { PHPhotoLibrary.shared().register(self) }

        let result = PHAsset.fetchAssets(with: options)
        lock.lock()
        fetchResult = result
        lock.unlock()

        let total = result.count
        for index in 0..<total {
            autoreleasepool {
                body(PhotoAssetReader.descriptor(for: result.object(at: index)), index, total)
            }
        }
    }

    // MARK: Review decks

    private static func reviewOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        return options
    }

    func earliestAssetDate() -> Date? {
        let options = Self.reviewOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: options).firstObject?.creationDate
    }

    func reviewItems(in windows: [DateInterval]) -> [ReviewItem] {
        guard !windows.isEmpty else { return [] }
        let options = Self.reviewOptions()
        let ranges = windows.map {
            NSPredicate(format: "creationDate >= %@ AND creationDate < %@", $0.start as NSDate, $0.end as NSDate)
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            options.predicate!,
            NSCompoundPredicate(orPredicateWithSubpredicates: ranges),
        ])
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var items: [ReviewItem] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            items.append(Self.reviewItem(asset))
        }
        return items
    }

    func reviewItems(ids: [String]) -> [ReviewItem] {
        var byID: [String: ReviewItem] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.idFetchOptions()).enumerateObjects { asset, _, _ in
            byID[asset.localIdentifier] = Self.reviewItem(asset)
        }
        return ids.compactMap { byID[$0] }
    }

    private static func reviewItem(_ asset: PHAsset) -> ReviewItem {
        ReviewItem(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            mediaKind: asset.mediaType == .video ? .video : .image,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive)
        )
    }

    func assetIndex() -> [AssetStamp] {
        let options = Self.reviewOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var index: [AssetStamp] = []
        let result = PHAsset.fetchAssets(with: options)
        index.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            index.append(AssetStamp(id: asset.localIdentifier, date: date))
        }
        return index
    }

    func members(for ids: [String]) -> [BucketMember] {
        let sizer: some SizeProvider = .standard
        var members: [BucketMember] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.idFetchOptions()).enumerateObjects { asset, _, _ in
            let descriptor = PhotoAssetReader.descriptor(for: asset)
            let size = sizer.size(of: descriptor) ?? AssetSize(bytes: 0, isEstimated: true)
            members.append(BucketMember(id: descriptor.id, size: size, availability: descriptor.availability))
        }
        return members
    }

    func analysisImage(for id: String, maxPixels: Int) -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.idFetchOptions()).firstObject
        else { return nil }
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        var result: CGImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: maxPixels, height: maxPixels),
            contentMode: .aspectFit, options: options
        ) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    // MARK: Changes

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        defer { lock.unlock() }
        guard let current = fetchResult, let details = changeInstance.changeDetails(for: current) else { return }
        fetchResult = details.fetchResultAfterChanges

        guard details.hasIncrementalChanges else {
            continuation.yield(.reload)
            return
        }
        let removed = Set(details.removedObjects.map(\.localIdentifier))
        let upserted: [any AssetDescriptor] = (details.insertedObjects + details.changedObjects)
            .map(PhotoAssetReader.descriptor(for:))
        guard !removed.isEmpty || !upserted.isEmpty else { return }
        continuation.yield(.incremental(removed: removed, upserted: upserted))
    }

    // MARK: Delete

    enum AssetError: Error {
        case notFound
    }

    func setFavorite(_ isFavorite: Bool, id: String) async throws {
        // A photo deleted elsewhere would otherwise "succeed" with nothing changed.
        guard PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.idFetchOptions()).firstObject != nil
        else { throw AssetError.notFound }
        try await PHPhotoLibrary.shared().performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.idFetchOptions()).firstObject
            else { return }
            PHAssetChangeRequest(for: asset).isFavorite = isFavorite
        }
    }

    /// Options for fetching by local identifier. Without `includeAllBurstAssets`,
    /// non-pick burst frames do not resolve.
    static func idFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        return options
    }

    func delete(ids: [String]) async throws -> DeleteOutcome {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.idFetchOptions())
        var submitted = Set<String>()
        assets.enumerateObjects { asset, _, _ in submitted.insert(asset.localIdentifier) }
        guard !submitted.isEmpty else { return .deleted([]) }
        let resolved = Array(submitted)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: resolved, options: Self.idFetchOptions())
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return .deleted(submitted)
        } catch {
            if Self.isUserCancel(error) { return .cancelled }
            throw error
        }
    }

    // MARK: Share

    func exportOriginal(id: String) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.idFetchOptions()).firstObject
        else { throw AssetError.notFound }
        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        let original = resources.first { $0.type == (isVideo ? .video : .photo) }
        let edited = resources.first { $0.type == (isVideo ? .fullSizeVideo : .fullSizePhoto) }
        guard let resource = edited ?? original ?? resources.first else { throw AssetError.notFound }

        // The edit is called FullSizeRender; give it the original's name with the edit's extension.
        var name = resource.originalFilename
        if let original, resource !== original {
            let stem = (original.originalFilename as NSString).deletingPathExtension
            name = stem + "." + (resource.originalFilename as NSString).pathExtension
        }

        let root = FileManager.default.temporaryDirectory.appending(path: "Share", directoryHint: .isDirectory)
        Self.removeOldExports(in: root)
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        return url
    }

    /// Drops exports from earlier shares. Recent ones stay, since a share sheet may still
    /// be reading them or another export may be writing.
    private static func removeOldExports(in root: URL, olderThan age: TimeInterval = 10 * 60) {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])
        else { return }
        let cutoff = Date.now.addingTimeInterval(-age)
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff { try? manager.removeItem(at: folder) }
        }
    }

    static func isUserCancel(_ error: any Error) -> Bool {
        if let photos = error as? PHPhotosError, photos.code == .userCancelled { return true }
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }
}
