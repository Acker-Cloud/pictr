import Foundation

/// A run of shots taken in quick succession: the burst you'd want to compare
/// before keeping one. Pure over `ReviewItem`, so decks of any order work.
enum Moment {
    /// Two shots further apart than this start a new moment.
    static let maxGap: TimeInterval = 120
    /// Keeps the compare tray scannable; a longer burst continues as the next moment.
    static let maxCount = 24

    /// The moment that starts at `start`: that item plus each following item within
    /// `maxGap` of the one before it. An undated item is a moment of one.
    static func run(in items: [ReviewItem], from start: Int,
                    maxGap: TimeInterval = maxGap, maxCount: Int = maxCount) -> Range<Int> {
        guard items.indices.contains(start) else { return start..<start }
        var end = start + 1
        while end < items.count, end - start < maxCount,
              let previous = items[end - 1].creationDate, let next = items[end].creationDate,
              abs(next.timeIntervalSince(previous)) <= maxGap {
            end += 1
        }
        return start..<end
    }
}
