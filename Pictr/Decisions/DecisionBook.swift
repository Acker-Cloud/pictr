import Foundation

/// Every keep/trash decision the user has made, keyed by asset local identifier.
/// Trash decisions form the Ready to Delete queue until applied.
struct DecisionBook: Sendable, Codable, Equatable {
    struct Record: Sendable, Codable, Equatable {
        var decision: Decision
        var decidedAt: Date
        var month: MonthKey?
    }

    struct Applied: Sendable, Codable, Equatable {
        var date: Date
        var count: Int
        var bytes: Int64
    }

    private(set) var records: [String: Record] = [:]
    private(set) var applied: [Applied] = []
    /// Decisions made per calendar day ("yyyy-MM-dd"), for streaks and daily counts.
    private(set) var activity: [String: Int] = [:]
    /// Training answers ("would you delete this?") that don't queue anything.
    private(set) var taste: [String: Decision] = [:]
    /// Photos you confirmed deleting. They leave the queue but stay "delete" examples.
    private(set) var deleted: Set<String> = []
    /// The active Cleanup Plan, if any.
    private(set) var plan: CleanupPlan?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decodeIfPresent([String: Record].self, forKey: .records) ?? [:]
        applied = try container.decodeIfPresent([Applied].self, forKey: .applied) ?? []
        activity = try container.decodeIfPresent([String: Int].self, forKey: .activity) ?? [:]
        taste = try container.decodeIfPresent([String: Decision].self, forKey: .taste) ?? [:]
        plan = try container.decodeIfPresent(CleanupPlan.self, forKey: .plan)
        deleted = try container.decodeIfPresent(Set<String>.self, forKey: .deleted) ?? []
    }

    mutating func startPlan(targetBytes: Int64, at date: Date = .now) {
        plan = CleanupPlan(targetBytes: targetBytes, startedAt: date)
    }

    mutating func endPlan() {
        plan = nil
    }

    /// Forgets Teach answers and deleted-photo examples. Keep and queue decisions stay.
    mutating func forgetLearning() {
        taste = [:]
        deleted = []
    }

    mutating func recordTaste(_ decision: Decision, for id: String) {
        taste[id] = decision
    }

    mutating func restoreTaste(_ id: String, to decision: Decision?) {
        taste[id] = decision
    }

    /// Every label the model can learn from: training answers plus real swipes.
    /// A real decision wins over a training answer for the same photo.
    var labels: [String: Bool] {
        var labels = taste.mapValues { $0 == .trash }
        for id in deleted { labels[id] = true }
        for (id, record) in records { labels[id] = record.decision == .trash }
        return labels
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func reviewedCount(on date: Date, calendar: Calendar = .current) -> Int {
        activity[Self.dayKey(date, calendar: calendar)] ?? 0
    }

    /// Consecutive days with at least one decision, ending today. If nothing yet
    /// today, the streak still counts through yesterday.
    func streak(endingOn today: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if reviewedCount(on: day, calendar: calendar) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while reviewedCount(on: day, calendar: calendar) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    var queue: [String] {
        records.filter { $0.value.decision == .trash }
            .sorted { $0.value.decidedAt < $1.value.decidedAt }
            .map(\.key)
    }

    var decidedIDs: Set<String> { Set(records.keys) }

    func decision(for id: String) -> Decision? { records[id]?.decision }

    func reviewedCount(in month: MonthKey) -> Int {
        records.values.filter { $0.month == month }.count
    }

    /// Favorites are protected and never enter the queue.
    @discardableResult
    mutating func record(_ decision: Decision, for item: ReviewItem, at date: Date = .now) -> Bool {
        if decision == .trash && item.isFavorite { return false }
        records[item.id] = Record(decision: decision, decidedAt: date, month: item.creationDate.map { MonthKey($0) })
        activity[Self.dayKey(date), default: 0] += 1
        return true
    }

    mutating func queue(ids: [String], at date: Date = .now) {
        for id in ids where records[id]?.decision != .keep {
            records[id] = Record(decision: .trash, decidedAt: date, month: records[id]?.month)
        }
    }

    mutating func restore(_ id: String, to record: Record?) {
        records[id] = record
    }

    func entry(for id: String) -> Record? { records[id] }

    mutating func unqueue(_ ids: some Sequence<String>) {
        for id in ids where records[id]?.decision == .trash { records[id] = nil }
    }

    /// After a confirmed delete: submitted IDs are gone from the library, and queued IDs
    /// that no longer resolved are gone too. Either way they leave the queue.
    mutating func finishApply(queued: [String], submitted: Set<String>, bytes: Int64, at date: Date = .now) {
        for id in queued { records[id] = nil }
        deleted.formUnion(submitted)
        if !submitted.isEmpty {
            applied.append(Applied(date: date, count: submitted.count, bytes: bytes))
        }
    }
}
