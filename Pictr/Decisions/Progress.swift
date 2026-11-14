import Foundation

/// A space goal measured in bytes moved to Recently Deleted since it started.
struct CleanupPlan: Sendable, Codable, Equatable {
    var targetBytes: Int64
    var startedAt: Date
}

struct ProgressStats: Sendable, Equatable {
    var reviewed: Int
    var kept: Int
    var queued: Int
    var movedCount: Int
    var movedBytes: Int64
    var cleanups: Int
    var streak: Int
    var bestStreak: Int
    var tasteAnswers: Int
}

extension DecisionBook {
    struct DayCount: Sendable, Equatable, Identifiable {
        var date: Date
        var count: Int
        var id: Date { date }
    }

    func stats(calendar: Calendar = .current, on date: Date = .now) -> ProgressStats {
        ProgressStats(
            // Every decision still on record plus confirmed deletes. The daily activity
            // log started later than decisions did, so it can't be the total.
            reviewed: records.count + deleted.count,
            kept: records.values.filter { $0.decision == .keep }.count,
            queued: queue.count,
            movedCount: applied.reduce(0) { $0 + $1.count },
            movedBytes: applied.reduce(0) { $0 + $1.bytes },
            cleanups: applied.count,
            streak: streak(endingOn: date, calendar: calendar),
            bestStreak: bestStreak(calendar: calendar),
            tasteAnswers: taste.count
        )
    }

    /// Longest run of consecutive days with at least one decision.
    func bestStreak(calendar: Calendar = .current) -> Int {
        let days = Set(activity.filter { $0.value > 0 }.keys)
        var best = 0
        for key in days {
            guard let date = Self.date(fromKey: key, calendar: calendar),
                  let previous = calendar.date(byAdding: .day, value: -1, to: date),
                  !days.contains(Self.dayKey(previous, calendar: calendar)) else { continue }
            // `key` starts a run; walk forward.
            var length = 0
            var cursor = date
            while days.contains(Self.dayKey(cursor, calendar: calendar)) {
                length += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, length)
        }
        return best
    }

    /// The last `count` days, oldest first, with zero for days without decisions.
    func recentDays(_ count: Int, endingOn date: Date = .now, calendar: Calendar = .current) -> [DayCount] {
        let end = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map {
                DayCount(date: $0, count: reviewedCount(on: $0, calendar: calendar))
            }
        }
    }

    var planProgress: Int64 {
        guard let plan else { return 0 }
        return applied.filter { $0.date >= plan.startedAt }.reduce(0) { $0 + $1.bytes }
    }

    private static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

enum Achievement: String, CaseIterable, Identifiable, Sendable {
    case firstSwipe, reviewed100, reviewed1000, reviewed10000
    case streak7, streak30
    case firstCleanup, moved1GB
    case tasteTrained

    var id: String { rawValue }

    struct Progress: Equatable {
        var unlocked: Bool
        var fraction: Double
        var label: String
    }

    var title: String {
        switch self {
        case .firstSwipe: "First swipe"
        case .reviewed100: "Hundred"
        case .reviewed1000: "Thousand"
        case .reviewed10000: "Archivist"
        case .streak7: "Week streak"
        case .streak30: "Month streak"
        case .firstCleanup: "First cleanup"
        case .moved1GB: "Gigabyte"
        case .tasteTrained: "Taught Pictr"
        }
    }

    var detail: String {
        switch self {
        case .firstSwipe: "Review a photo"
        case .reviewed100: "Review 100 photos"
        case .reviewed1000: "Review 1,000 photos"
        case .reviewed10000: "Review 10,000 photos"
        case .streak7: "Review 7 days in a row"
        case .streak30: "Review 30 days in a row"
        case .firstCleanup: "Confirm a delete from Ready to Delete"
        case .moved1GB: "Move 1 GB to Recently Deleted"
        case .tasteTrained: "Answer 20 Teach questions"
        }
    }

    var systemImage: String {
        switch self {
        case .firstSwipe: "hand.draw"
        case .reviewed100, .reviewed1000, .reviewed10000: "rectangle.stack"
        case .streak7, .streak30: "flame"
        case .firstCleanup: "trash"
        case .moved1GB: "internaldrive"
        case .tasteTrained: "brain"
        }
    }

    func progress(_ stats: ProgressStats) -> Progress {
        switch self {
        case .firstSwipe: count(stats.reviewed, of: 1)
        case .reviewed100: count(stats.reviewed, of: 100)
        case .reviewed1000: count(stats.reviewed, of: 1_000)
        case .reviewed10000: count(stats.reviewed, of: 10_000)
        case .streak7: count(stats.bestStreak, of: 7)
        case .streak30: count(stats.bestStreak, of: 30)
        case .firstCleanup: count(stats.cleanups, of: 1)
        case .tasteTrained: count(stats.tasteAnswers, of: 20)
        case .moved1GB:
            Progress(unlocked: stats.movedBytes >= 1_000_000_000,
                     fraction: min(Double(stats.movedBytes) / 1_000_000_000, 1),
                     label: "\(ByteFormat.string(stats.movedBytes)) of 1 GB")
        }
    }

    private func count(_ value: Int, of target: Int) -> Progress {
        Progress(unlocked: value >= target,
                 fraction: min(Double(value) / Double(target), 1),
                 label: "\(min(value, target).formatted()) of \(target.formatted())")
    }
}
