import Foundation

/// Pure bucketing rules over sized assets. No PhotoKit.
enum Bucketer {
    static let largeVideoThreshold: Int64 = 100_000_000

    static func buckets(
        for assets: [ScannedAsset],
        analysis: [String: AssetAnalysis] = [:],
        similar: [[String]] = [],
        maybeDelete: [(id: String, reason: String)] = [],
        settings: BucketSettings = BucketSettings()
    ) -> BucketSet {
        let eligible = assets.filter { !$0.descriptor.isFavorite && !$0.descriptor.isHidden }
        let byID = Dictionary(assets.map { ($0.descriptor.id, $0) }, uniquingKeysWith: { a, _ in a })
        let stills = eligible.filter { $0.descriptor.mediaKind == .image && !$0.descriptor.isScreenshot }

        let screenshots = eligible.filter {
            $0.descriptor.mediaKind == .image && $0.descriptor.isScreenshot
        }

        let suggestedBurstIDs = burstExtraIDs(in: assets)
        let burstExtras = eligible.filter { suggestedBurstIDs.contains($0.descriptor.id) }

        let largeVideos = eligible
            .filter { $0.descriptor.mediaKind == .video && $0.size.bytes >= settings.largeVideoBytes }
            .sorted { $0.size.bytes > $1.size.bytes }

        let screenRecordings = eligible.filter { $0.descriptor.mediaKind == .video && $0.descriptor.isScreenRecording }

        let blurry = stills.filter {
            guard let result = analysis[$0.descriptor.id], let sharpness = result.sharpness else { return false }
            let smoothButGood = (result.aestheticScore ?? -1) >= settings.blurAestheticsCeiling
            return sharpness < settings.blur.threshold && !smoothButGood
        }
        let blurryIDs = Set(blurry.map(\.descriptor.id))
        let utility = stills.filter { analysis[$0.descriptor.id]?.isUtility == true }
        let lowQuality = stills.filter {
            guard let result = analysis[$0.descriptor.id], !result.isUtility, let score = result.aestheticScore else { return false }
            return score < settings.lowQualityScore && !blurryIDs.contains($0.descriptor.id)
        }

        // Similar groups: hidden frames drop out, favorites stay as keepers.
        var groups: [SimilarGroup] = []
        for ids in similar {
            let members = ids.filter { byID[$0].map { !$0.descriptor.isHidden } ?? false }
            guard members.count > 1 else { continue }
            let keepers = SimilarGrouper.keepers(
                in: members,
                isFavorite: { byID[$0]?.descriptor.isFavorite ?? false },
                score: { analysis[$0]?.aestheticScore },
                pixels: { id in byID[id].map { $0.descriptor.pixelWidth * $0.descriptor.pixelHeight } ?? 0 }
            )
            let group = SimilarGroup(memberIDs: members, keeperIDs: keepers)
            if !group.extraIDs.isEmpty { groups.append(group) }
        }
        let similarMembers = groups.flatMap(\.extraIDs).compactMap { byID[$0] }

        let eligibleIDs = Set(eligible.map(\.descriptor.id))
        let suggested = maybeDelete.filter { eligibleIDs.contains($0.id) }

        return BucketSet(buckets: [
            Bucket(kind: .maybeDelete, members: suggested.compactMap { byID[$0.id] }.map(member)),
            Bucket(kind: .similar, members: similarMembers.map(member)),
            Bucket(kind: .screenshots, members: newestFirst(screenshots).map(member)),
            Bucket(kind: .burstExtras, members: newestFirst(burstExtras).map(member)),
            Bucket(kind: .blurry, members: blurry.sorted {
                (analysis[$0.descriptor.id]?.sharpness ?? 0) < (analysis[$1.descriptor.id]?.sharpness ?? 0)
            }.map(member)),
            Bucket(kind: .lowQuality, members: newestFirst(lowQuality).map(member)),
            Bucket(kind: .utility, members: newestFirst(utility).map(member)),
            Bucket(kind: .largeVideos, members: largeVideos.map(member)),
            Bucket(kind: .screenRecordings, members: newestFirst(screenRecordings).map(member)),
        ], similarGroups: groups, reasons: Dictionary(suggested.map { ($0.id, $0.reason) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Frames to suggest from each burst: everything except picks and the cover frame.
    /// With neither, the first frame is kept. Computed over all assets so a
    /// favorite or hidden frame still counts as part of its burst.
    static func burstExtraIDs(in assets: [ScannedAsset]) -> Set<String> {
        let groups = Dictionary(grouping: assets.map(\.descriptor).filter { $0.burstIdentifier != nil }) {
            $0.burstIdentifier!
        }
        var result = Set<String>()
        for frames in groups.values where frames.count > 1 {
            let picks = frames.filter { $0.isBurstPick || $0.representsBurst }
            let keep: Set<String>
            if picks.isEmpty {
                let first = frames.min { lhs, rhs in
                    let l = lhs.creationDate ?? .distantFuture
                    let r = rhs.creationDate ?? .distantFuture
                    return l == r ? lhs.id < rhs.id : l < r
                }
                keep = first.map { [$0.id] } ?? []
            } else {
                keep = Set(picks.map(\.id))
            }
            for frame in frames where !keep.contains(frame.id) {
                result.insert(frame.id)
            }
        }
        return result
    }

    private static func newestFirst(_ assets: [ScannedAsset]) -> [ScannedAsset] {
        assets.sorted {
            let l = $0.descriptor.creationDate ?? .distantPast
            let r = $1.descriptor.creationDate ?? .distantPast
            return l == r ? $0.descriptor.id < $1.descriptor.id : l > r
        }
    }

    private static func member(_ asset: ScannedAsset) -> BucketMember {
        BucketMember(id: asset.descriptor.id, size: asset.size, availability: asset.descriptor.availability)
    }
}
