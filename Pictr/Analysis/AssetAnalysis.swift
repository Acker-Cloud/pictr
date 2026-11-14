import Foundation

/// What on-device analysis learned about one photo. Pure values, no Vision types.
struct AssetAnalysis: Sendable, Equatable {
    /// Vision aesthetics, -1 (poor) to 1 (great). Nil if the request failed.
    var aestheticScore: Float?
    /// Vision's utility flag: receipts, documents, screenshots of text.
    var isUtility: Bool
    /// Laplacian variance at a fixed 512 px long side. Lower is blurrier.
    var sharpness: Double?
}

enum BlurSensitivity: String, Sendable, CaseIterable, Identifiable, Codable {
    case low, medium, high
    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Only very blurry"
        case .medium: "Balanced"
        case .high: "Anything soft"
        }
    }

    /// Photos with sharpness below this are blurry.
    var threshold: Double {
        switch self {
        case .low: 40
        case .medium: 80
        case .high: 130
        }
    }
}

/// User-tunable bucket rules.
struct BucketSettings: Sendable, Equatable, Codable {
    /// How far back Cleanup looks. 0 means the whole library.
    var windowDays: Int = 30
    var largeVideoBytes: Int64 = Bucketer.largeVideoThreshold
    var blur: BlurSensitivity = .medium
    /// Below this aesthetics score (and not utility) a photo is low quality.
    var lowQualityScore: Float = -0.3
    /// Low sharpness with an aesthetics score at or above this is a smooth subject
    /// (sky, minimal shot), not blur. Measured: smooth gradient 0.76, real blur -0.25.
    var blurAestheticsCeiling: Float = 0.3
}

enum BlurScorer {
    /// Variance of the 4-neighbour Laplacian over an 8-bit grayscale image.
    /// Sharp edges give large second derivatives; blur flattens them.
    static func laplacianVariance(gray: [UInt8], width: Int, height: Int) -> Double? {
        guard width >= 3, height >= 3, gray.count >= width * height else { return nil }
        var sum = 0.0
        var sumSquares = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let i = row + x
                let value = Double(gray[i - width]) + Double(gray[i + width]) + Double(gray[i - 1]) + Double(gray[i + 1])
                    - 4 * Double(gray[i])
                sum += value
                sumSquares += value * value
                count += 1
            }
        }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }
}

/// A run of near-identical shots with the photos worth keeping.
struct SimilarGroup: Sendable, Equatable, Identifiable {
    var memberIDs: [String]
    var keeperIDs: Set<String>
    var id: String { memberIDs.first ?? "" }
    var extraIDs: [String] { memberIDs.filter { !keeperIDs.contains($0) } }
}

enum SimilarGrouper {
    /// Shots further apart than this are never grouped.
    static let window: TimeInterval = 10 * 60
    /// Feature-print distance under which two shots count as the same moment.
    /// Measured on iPhone (VisionTests): near-duplicates 0.001-0.003, a different
    /// shot with the same palette 0.48, unrelated 0.7-1.0.
    static let threshold: Double = 0.30

    struct Candidate: Sendable {
        var id: String
        var date: Date
    }

    /// Groups candidates (any order) whose neighbours in time are within `threshold`.
    /// `distance` returns nil when it cannot compare two items.
    static func groups(
        _ candidates: [Candidate],
        window: TimeInterval = window,
        threshold: Double = threshold,
        distance: (String, String) -> Double?
    ) -> [[String]] {
        let sorted = candidates.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        var parent = Array(sorted.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in sorted.indices {
            var j = i + 1
            while j < sorted.count, sorted[j].date.timeIntervalSince(sorted[i].date) <= window {
                if let d = distance(sorted[i].id, sorted[j].id), d < threshold {
                    parent[root(j)] = root(i)
                }
                j += 1
            }
        }
        let clusters = Dictionary(grouping: sorted.indices, by: root)
        return clusters.values
            .filter { $0.count > 1 }
            .map { $0.sorted().map { sorted[$0].id } }
            .sorted { $0[0] < $1[0] }
    }

    /// Keeps every favorite; otherwise the best aesthetics score, then the most pixels.
    static func keepers(
        in members: [String],
        isFavorite: (String) -> Bool,
        score: (String) -> Float?,
        pixels: (String) -> Int
    ) -> Set<String> {
        let favorites = Set(members.filter(isFavorite))
        if !favorites.isEmpty { return favorites }
        let best = members.max { lhs, rhs in
            let l = score(lhs) ?? -.infinity, r = score(rhs) ?? -.infinity
            return l == r ? pixels(lhs) < pixels(rhs) : l < r
        }
        return best.map { [$0] } ?? []
    }
}
