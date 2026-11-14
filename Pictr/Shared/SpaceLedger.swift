import Foundation

/// Session space accounting. Nothing here is space returned yet: deleted items sit in
/// Recently Deleted for 30 days, and iCloud-only items take little local space.
struct SpaceLedger: Sendable, Equatable {
    private(set) var queued: [BucketMember] = []
    private(set) var moved: [BucketMember] = []

    var queuedBytes: Int64 { queued.reduce(0) { $0 + $1.size.bytes } }
    var movedBytes: Int64 { moved.reduce(0) { $0 + $1.size.bytes } }
    var movedCount: Int { moved.count }
    var movedCloudOnlyBytes: Int64 {
        moved.filter { $0.availability == .cloudOnly }.reduce(0) { $0 + $1.size.bytes }
    }

    mutating func queue(_ members: [BucketMember]) {
        queued = members
    }

    mutating func finish(_ outcome: DeleteOutcome) {
        if case let .deleted(ids) = outcome {
            moved.append(contentsOf: queued.filter { ids.contains($0.id) })
        }
        queued = []
    }

    mutating func fail() {
        queued = []
    }
}
