import Foundation

/// What a photo shows, from Vision's on-device classifier: identifier to confidence.
typealias SubjectTags = [String: Float]

/// Learns which subjects you delete and keep from your own decisions.
/// Each tag's evidence is weighted by classifier confidence; scores are smoothed
/// log-odds, so a tag needs a few photos behind it before it counts.
enum SubjectTaste {
    static let minConfidence: Float = 0.3
    static let minEvidence = 3.0

    struct Tally: Equatable {
        var deletes = 0.0
        var keeps = 0.0
        var total: Double { deletes + keeps }
        /// Smoothed log-odds of delete over keep.
        var logOdds: Double { log((deletes + 1) / (keeps + 1)) }
    }

    struct Score: Equatable {
        /// -1 (subjects you keep) to 1 (subjects you delete).
        var value: Double
        /// The subject that pushed hardest toward delete, when the score leans delete.
        var tag: String?
    }

    static func tallies(labels: [String: Bool], tags: [String: SubjectTags]) -> [String: Tally] {
        var tallies: [String: Tally] = [:]
        for (id, deleted) in labels {
            guard let photoTags = tags[id] else { continue }
            for (tag, confidence) in photoTags where confidence >= minConfidence {
                if deleted { tallies[tag, default: Tally()].deletes += Double(confidence) }
                else { tallies[tag, default: Tally()].keeps += Double(confidence) }
            }
        }
        return tallies
    }

    /// `own` is this photo's label when it is itself a training example, so its
    /// vote is removed before scoring it (leave-one-out).
    static func score(_ photoTags: SubjectTags, tallies: [String: Tally], own: Bool? = nil) -> Score {
        var weighted = 0.0
        var weight = 0.0
        var best: (tag: String, push: Double)?
        for (tag, confidence) in photoTags where confidence >= minConfidence {
            guard var tally = tallies[tag] else { continue }
            if let own {
                if own { tally.deletes -= Double(confidence) } else { tally.keeps -= Double(confidence) }
            }
            guard tally.total >= minEvidence - 1e-9 else { continue }
            let c = Double(confidence)
            let logOdds = tally.logOdds
            weighted += c * logOdds
            weight += c
            if logOdds > 0, c * logOdds > (best?.push ?? 0) { best = (tag, c * logOdds) }
        }
        guard weight > 0 else { return Score(value: 0, tag: nil) }
        let value = min(max(weighted / weight / 2, -1), 1)
        return Score(value: value, tag: value > 0 ? best?.tag : nil)
    }

    static func displayName(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }
}

/// Votes from the photos you've already decided that look most like this one
/// (Vision feature-print distance). Positive means its look-alikes were deleted.
enum LookalikeTaste {
    static let neighbors = 7
    /// Provisional. Measured on device: near-duplicates 0.001-0.003, same palette
    /// 0.48, unrelated 0.7-1.0. Re-measure on a real library.
    static let maxDistance = 0.6

    static func score(id: String, labeled: [String: Bool], distance: (String) -> Double?) -> Double {
        var near: [(d: Double, deleted: Bool)] = []
        for (other, deleted) in labeled where other != id {
            if let d = distance(other), d < maxDistance { near.append((d, deleted)) }
        }
        guard !near.isEmpty else { return 0 }
        near.sort { $0.d < $1.d }
        let nearest = near.prefix(neighbors)
        var vote = 0.0
        var weight = 0.0
        for neighbor in nearest {
            let w = 1 - neighbor.d / maxDistance
            vote += w * (neighbor.deleted ? 1 : -1)
            weight += w
        }
        guard weight > 0 else { return 0 }
        let coverage = min(Double(nearest.count) / 3, 1)
        return vote / weight * coverage
    }
}

/// Plain facts about what Pictr has learned, for Settings and the optional
/// Apple Intelligence summary.
struct TasteSummary: Equatable, Sendable {
    struct Subject: Equatable, Sendable {
        var name: String
        var deletes: Int
        var keeps: Int
    }

    var deletes: [Subject]
    var keeps: [Subject]
    var labelCount: Int
    var analyzedLabelCount: Int

    static let empty = TasteSummary(deletes: [], keeps: [], labelCount: 0, analyzedLabelCount: 0)

    init(deletes: [Subject], keeps: [Subject], labelCount: Int, analyzedLabelCount: Int) {
        self.deletes = deletes
        self.keeps = keeps
        self.labelCount = labelCount
        self.analyzedLabelCount = analyzedLabelCount
    }

    init(labels: [String: Bool], tags: [String: SubjectTags], limit: Int = 6) {
        let tallies = SubjectTaste.tallies(labels: labels, tags: tags)
            .filter { $0.value.total >= SubjectTaste.minEvidence }
        func subjects(_ keep: (SubjectTaste.Tally) -> Bool, by order: @escaping (SubjectTaste.Tally) -> Double) -> [Subject] {
            tallies.filter { keep($0.value) }
                .sorted { order($0.value) > order($1.value) }
                .prefix(limit)
                .map { Subject(name: SubjectTaste.displayName($0.key),
                               deletes: Int($0.value.deletes.rounded()), keeps: Int($0.value.keeps.rounded())) }
        }
        deletes = subjects({ $0.logOdds > 0.5 }, by: { $0.logOdds * $0.total })
        keeps = subjects({ $0.logOdds < -0.5 }, by: { -$0.logOdds * $0.total })
        labelCount = labels.count
        analyzedLabelCount = labels.keys.filter { tags[$0] != nil }.count
    }
}
