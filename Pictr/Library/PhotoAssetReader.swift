import Foundation
import Photos

struct PhotoAssetDescriptor: AssetDescriptor {
    var id: String
    var creationDate: Date?
    var mediaKind: AssetMediaKind
    var isScreenshot: Bool
    var isScreenRecording: Bool
    var isLivePhoto: Bool
    var isFavorite: Bool
    var isHidden: Bool
    var burstIdentifier: String?
    var isBurstPick: Bool
    var representsBurst: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: TimeInterval
    var uniformTypeIdentifier: String?
    var resources: [ResourceRecord]
}

/// Converts PHAsset to plain values. Reads two private PHAssetResource keys
/// defensively; when a key is missing the value is nil and callers fall back.
enum PhotoAssetReader {
    static func descriptor(for asset: PHAsset) -> PhotoAssetDescriptor {
        let resources = PHAssetResource.assetResources(for: asset)
        let records = resources.map(record)
        let primary = resources.first { $0.type == .photo || $0.type == .video }

        let mediaKind: AssetMediaKind = switch asset.mediaType {
        case .image: .image
        case .video: .video
        default: .other
        }

        return PhotoAssetDescriptor(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            mediaKind: mediaKind,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isScreenRecording: asset.mediaSubtypes.contains(.videoScreenRecording),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            burstIdentifier: asset.burstIdentifier,
            isBurstPick: !asset.burstSelectionTypes.isDisjoint(with: [.userPick, .autoPick]),
            representsBurst: asset.representsBurst,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            uniformTypeIdentifier: primary?.uniformTypeIdentifier,
            resources: records
        )
    }

    static func record(for resource: PHAssetResource) -> ResourceRecord {
        let kind: ResourceRecord.Kind = switch resource.type {
        case .photo, .alternatePhoto: .photo
        case .video: .video
        case .pairedVideo, .fullSizePairedVideo, .adjustmentBasePairedVideo: .pairedVideo
        case .fullSizePhoto, .adjustmentBasePhoto: .fullSizePhoto
        case .fullSizeVideo, .adjustmentBaseVideo: .fullSizeVideo
        default: .other
        }
        return ResourceRecord(
            kind: kind,
            uniformTypeIdentifier: resource.uniformTypeIdentifier,
            byteCount: privateInt64(resource, getter: "fileSize"),
            isLocallyAvailable: privateBool(resource, getters: ["locallyAvailable", "isLocallyAvailable"])
        )
    }

    private static func privateInt64(_ object: NSObject, getter: String) -> Int64? {
        guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
        return (object.value(forKey: getter) as? NSNumber)?.int64Value
    }

    private static func privateBool(_ object: NSObject, getters: [String]) -> Bool? {
        for getter in getters where object.responds(to: NSSelectorFromString(getter)) {
            if let number = object.value(forKey: getter) as? NSNumber { return number.boolValue }
        }
        return nil
    }
}
