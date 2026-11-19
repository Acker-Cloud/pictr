import Foundation

enum BucketKind: String, Sendable, CaseIterable, Identifiable {
    case maybeDelete
    case similar
    case duplicates
    case screenshots
    case burstExtras
    case blurry
    case lowQuality
    case utility
    case largeVideos
    case screenRecordings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maybeDelete: "Maybe Delete"
        case .similar: "Similar shots"
        case .duplicates: "Duplicates"
        case .screenshots: "Screenshots"
        case .burstExtras: "Burst extras"
        case .blurry: "Blurry"
        case .lowQuality: "Low quality"
        case .utility: "Utility shots"
        case .largeVideos: "Large videos"
        case .screenRecordings: "Screen recordings"
        }
    }

    /// Needs on-device Vision analysis before it can fill.
    var needsAnalysis: Bool {
        switch self {
        case .maybeDelete, .similar, .blurry, .lowQuality, .utility: true
        case .duplicates, .screenshots, .burstExtras, .largeVideos, .screenRecordings: false
        }
    }

    var reason: String {
        switch self {
        case .maybeDelete: "Picked by what Pictr has learned from your swipes. Each shows its main reason. Suggestions only change when you update them."
        case .similar: "Near-identical shots taken close together. The best of each set is kept and can't be selected."
        case .duplicates: "Exact copies: the same size, the same second, the same file size. One of each is kept and can't be selected."
        case .screenshots: "Screen captures."
        case .burstExtras: "Burst frames that were not picked. The picked frame stays."
        case .blurry: "Photos that scored soft on this iPhone's sharpness check. Scores are estimates, so look before you delete."
        case .lowQuality: "Photos Vision rated poorly: dark, tilted, badly framed. Estimates, not verdicts."
        case .utility: "Receipts, documents, whiteboards and other shots taken to remember something."
        case .largeVideos: "Your biggest videos, largest first."
        case .screenRecordings: "Recordings of this iPhone's screen."
        }
    }

    var systemImage: String {
        switch self {
        case .maybeDelete: "questionmark.square.dashed"
        case .similar: "square.on.square"
        case .duplicates: "plus.square.on.square"
        case .screenshots: "camera.viewfinder"
        case .burstExtras: "square.stack.3d.down.right"
        case .blurry: "camera.aperture"
        case .lowQuality: "hand.thumbsdown"
        case .utility: "doc.text.viewfinder"
        case .largeVideos: "video"
        case .screenRecordings: "record.circle"
        }
    }
}

struct BucketMember: Sendable, Identifiable, Equatable {
    var id: String
    var size: AssetSize
    var availability: Availability
}

struct Bucket: Sendable, Identifiable, Equatable {
    var kind: BucketKind
    var members: [BucketMember]

    var id: BucketKind { kind }
    var count: Int { members.count }
    var totalBytes: Int64 { members.reduce(0) { $0 + $1.size.bytes } }
    var hasEstimates: Bool { members.contains { $0.size.isEstimated } }
}

struct BucketSet: Sendable, Equatable {
    var buckets: [Bucket]
    var similarGroups: [SimilarGroup] = []
    var duplicateGroups: [SimilarGroup] = []
    /// Why each Maybe Delete member was suggested.
    var reasons: [String: String] = [:]

    static let empty = BucketSet(buckets: BucketKind.allCases.map { Bucket(kind: $0, members: []) })

    subscript(kind: BucketKind) -> Bucket {
        buckets.first { $0.kind == kind } ?? Bucket(kind: kind, members: [])
    }

    /// Members across all buckets, each asset counted once.
    var uniqueMembers: [BucketMember] {
        var seen = Set<String>()
        return buckets.flatMap(\.members).filter { seen.insert($0.id).inserted }
    }

    var reclaimableBytes: Int64 { uniqueMembers.reduce(0) { $0 + $1.size.bytes } }
    var reclaimableHasEstimates: Bool { uniqueMembers.contains { $0.size.isEstimated } }
    var cloudOnlyBytes: Int64 {
        uniqueMembers.filter { $0.availability == .cloudOnly }.reduce(0) { $0 + $1.size.bytes }
    }

    /// The Duplicates or Similar shots set a photo belongs to, so a deck can offer to compare
    /// it. Exact copies come first. Call on a set already passed through `excluding`.
    func lookalikes(of id: String) -> (kind: BucketKind, group: SimilarGroup)? {
        if let group = duplicateGroups.first(where: { $0.memberIDs.contains(id) }) { return (.duplicates, group) }
        if let group = similarGroups.first(where: { $0.memberIDs.contains(id) }) { return (.similar, group) }
        return nil
    }
}

extension BucketSet {
    /// Removes assets the user already decided on (kept or queued). A group whose
    /// keepers are all queued no longer protects anything, so it and its extras drop out
    /// rather than stay preselected beside a keeper that is going.
    func excluding(_ ids: Set<String>, queued: Set<String> = []) -> BucketSet {
        guard !ids.isEmpty else { return self }
        func remaining(_ groups: [SimilarGroup]) -> (groups: [SimilarGroup], orphans: Set<String>) {
            var orphans = Set<String>()
            let kept = groups.compactMap { group -> SimilarGroup? in
                if !group.keeperIDs.isEmpty && group.keeperIDs.isSubset(of: queued) {
                    orphans.formUnion(group.extraIDs)
                    return nil
                }
                let members = group.memberIDs.filter { !ids.contains($0) || group.keeperIDs.contains($0) }
                let extras = members.filter { !group.keeperIDs.contains($0) }
                return extras.isEmpty ? nil : SimilarGroup(memberIDs: members, keeperIDs: group.keeperIDs)
            }
            return (kept, orphans)
        }
        let similar = remaining(similarGroups)
        let duplicates = remaining(duplicateGroups)
        return BucketSet(
            buckets: buckets.map { bucket in
                let orphans = bucket.kind == .similar ? similar.orphans
                    : bucket.kind == .duplicates ? duplicates.orphans : []
                return Bucket(kind: bucket.kind,
                              members: bucket.members.filter { !ids.contains($0.id) && !orphans.contains($0.id) })
            },
            similarGroups: similar.groups,
            duplicateGroups: duplicates.groups,
            reasons: reasons
        )
    }
}
