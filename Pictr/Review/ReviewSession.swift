import Foundation

enum Decision: String, Sendable, Codable, Equatable {
    case keep
    case trash
}

/// A swipe deck: walks a fixed list, records decisions, undoes them in order.
/// A compare decides a whole moment as one action, and undo walks it back whole.
struct ReviewSession: Sendable {
    struct Step: Sendable, Equatable {
        var item: ReviewItem
        var decision: Decision
    }

    let items: [ReviewItem]
    private(set) var index = 0
    private(set) var history: [Step] = []
    /// Steps per action, so undo takes back a compare in one go.
    private var actionSizes: [Int] = []

    init(items: [ReviewItem]) {
        self.items = items
    }

    var current: ReviewItem? { index < items.count ? items[index] : nil }
    var upcoming: [ReviewItem] { Array(items.dropFirst(index + 1).prefix(3)) }
    var isFinished: Bool { index >= items.count }
    var canUndo: Bool { !history.isEmpty }
    var keptCount: Int { history.filter { $0.decision == .keep }.count }
    var trashedCount: Int { history.filter { $0.decision == .trash }.count }

    @discardableResult
    mutating func decide(_ decision: Decision) -> Step? {
        guard let item = current else { return nil }
        let step = Step(item: item, decision: decision)
        history.append(step)
        index += 1
        actionSizes.append(1)
        return step
    }

    /// Decides the next `batch.count` items, in order, as one action.
    @discardableResult
    mutating func decide(batch: [Decision]) -> [Step] {
        let count = min(batch.count, items.count - index)
        guard count > 0 else { return [] }
        let steps = (0..<count).map { Step(item: items[index + $0], decision: batch[$0]) }
        history += steps
        index += count
        actionSizes.append(count)
        return steps
    }

    /// Takes back the last action: one swipe, or a whole compare. Steps come back in deck order.
    @discardableResult
    mutating func undo() -> [Step] {
        guard let count = actionSizes.popLast() else { return [] }
        let steps = Array(history.suffix(count))
        history.removeLast(count)
        index -= count
        return steps
    }
}
