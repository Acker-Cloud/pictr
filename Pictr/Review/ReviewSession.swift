import Foundation

enum Decision: String, Sendable, Codable, Equatable {
    case keep
    case trash
}

/// A swipe deck: walks a fixed list, records decisions, undoes them in order.
struct ReviewSession: Sendable {
    struct Step: Sendable, Equatable {
        var item: ReviewItem
        var decision: Decision
        /// A keep that also marked the photo a favorite in Photos.
        var favorited = false
    }

    let items: [ReviewItem]
    private(set) var index = 0
    private(set) var history: [Step] = []

    init(items: [ReviewItem]) {
        self.items = items
    }

    var current: ReviewItem? { index < items.count ? items[index] : nil }
    var upcoming: [ReviewItem] { Array(items.dropFirst(index + 1).prefix(3)) }
    var isFinished: Bool { index >= items.count }
    var canUndo: Bool { !history.isEmpty }
    var keptCount: Int { history.filter { $0.decision == .keep }.count }
    var trashedCount: Int { history.filter { $0.decision == .trash }.count }
    var favoritedCount: Int { history.filter(\.favorited).count }

    @discardableResult
    mutating func decide(_ decision: Decision, favorited: Bool = false) -> Step? {
        guard let item = current else { return nil }
        let step = Step(item: item, decision: decision, favorited: favorited)
        history.append(step)
        index += 1
        return step
    }

    @discardableResult
    mutating func undo() -> Step? {
        guard let step = history.popLast() else { return nil }
        index -= 1
        return step
    }
}
