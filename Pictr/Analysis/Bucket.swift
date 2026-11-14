import Foundation

enum BucketKind: String, Sendable, CaseIterable, Identifiable {
    case maybeDelete
    case similar
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
        case .screenshots, .burstExtras, .largeVideos, .screenRecordings: false
        }
    }

    var reason: String {
        switch self {
        case .maybeDelete: "Picked by what Pictr has learned from your swipes. Each shows its main reason. Suggestions only change when you update them."
        case .similar: "Near-identical shots taken close together. The best of each set is kept and can't be selected."
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
}

extension BucketSet {
    /// Removes assets the user already decided on (kept or queued).
    func excluding(_ ids: Set<String>) -> BucketSet {
        guard !ids.isEmpty else { return self }
        let groups = similarGroups.compactMap { group -> SimilarGroup? in
            let members = group.memberIDs.filter { !ids.contains($0) || group.keeperIDs.contains($0) }
            let extras = members.filter { !group.keeperIDs.contains($0) }
            return extras.isEmpty ? nil : SimilarGroup(memberIDs: members, keeperIDs: group.keeperIDs)
        }
        return BucketSet(
            buckets: buckets.map { Bucket(kind: $0.kind, members: $0.members.filter { !ids.contains($0.id) }) },
            similarGroups: groups,
            reasons: reasons
        )
    }
}
