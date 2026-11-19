import Foundation

/// Exact copies by metadata alone: same kind, pixel size, capture second, duration and
/// primary-file byte count. Needs no Vision, so it works on any library at once.
enum DuplicateFinder {
    private struct Key: Hashable {
        var kind: AssetMediaKind
        var isLivePhoto: Bool
        var width: Int
        var height: Int
        var second: Int64
        var tenthsOfSecond: Int64
        var bytes: Int64
    }

    static func groups(in assets: [ScannedAsset]) -> [SimilarGroup] {
        var byKey: [Key: [any AssetDescriptor]] = [:]
        for asset in assets {
            if let key = key(for: asset.descriptor) { byKey[key, default: []].append(asset.descriptor) }
        }
        return byKey.values
            .filter { $0.count > 1 }
            .compactMap(group)
            .sorted { $0.id < $1.id }
    }

    private static func key(for asset: any AssetDescriptor) -> Key? {
        guard asset.mediaKind != .other, !asset.isHidden, asset.burstIdentifier == nil,
              let date = asset.creationDate, let bytes = primaryBytes(asset)
        else { return nil }
        return Key(kind: asset.mediaKind, isLivePhoto: asset.isLivePhoto,
                   width: asset.pixelWidth, height: asset.pixelHeight,
                   second: Int64(date.timeIntervalSince1970.rounded(.down)),
                   tenthsOfSecond: Int64((asset.duration * 10).rounded()), bytes: bytes)
    }

    /// Size of the original photo or video file, only when every one is known. Zero means
    /// Photos didn't really say, so it never matches.
    private static func primaryBytes(_ asset: any AssetDescriptor) -> Int64? {
        let primary = asset.resources.filter { $0.kind == .photo || $0.kind == .video }
        guard !primary.isEmpty else { return nil }
        var total: Int64 = 0
        for resource in primary {
            guard let bytes = resource.byteCount, bytes > 0 else { return nil }
            total += bytes
        }
        return total
    }

    /// Keeper first: favorites, else an edited copy, else the lowest ID.
    private static func group(_ copies: [any AssetDescriptor]) -> SimilarGroup? {
        let sorted = copies.sorted { $0.id < $1.id }
        let favorites = sorted.filter(\.isFavorite).map(\.id)
        let keepers: [String]
        if !favorites.isEmpty {
            keepers = favorites
        } else if let edited = sorted.first(where: isEdited) {
            keepers = [edited.id]
        } else {
            keepers = [sorted[0].id]
        }
        let extras = sorted.map(\.id).filter { !keepers.contains($0) }
        guard !extras.isEmpty else { return nil }
        return SimilarGroup(memberIDs: keepers + extras, keeperIDs: Set(keepers))
    }

    private static func isEdited(_ asset: any AssetDescriptor) -> Bool {
        asset.resources.contains { $0.kind == .fullSizePhoto || $0.kind == .fullSizeVideo }
    }
}
