import Foundation

/// A random deck from anywhere in the library.
enum Shuffle {
    /// Deck size when Photos per deck is set to all photos.
    static let defaultCount = 25

    /// Up to `count` distinct undecided IDs in random order.
    static func pick(_ ids: [String], excluding decided: Set<String>, count: Int,
                     using generator: inout some RandomNumberGenerator) -> [String] {
        guard count > 0 else { return [] }
        var seen = Set<String>()
        var pool = ids.filter { !decided.contains($0) && seen.insert($0).inserted }
        // Partial Fisher-Yates: only the first `count` slots need shuffling.
        let n = min(count, pool.count)
        for i in 0..<n {
            let j = Int.random(in: i..<pool.count, using: &generator)
            pool.swapAt(i, j)
        }
        return Array(pool.prefix(n))
    }

    static func pick(_ ids: [String], excluding decided: Set<String>, count: Int) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return pick(ids, excluding: decided, count: count, using: &generator)
    }
}
