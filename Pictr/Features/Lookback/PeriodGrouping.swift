import Foundation

/// One photo's identity and capture date: all Lookback needs to group.
struct AssetStamp: Sendable, Codable, Equatable {
    var id: String
    var date: Date
}

enum PeriodUnit: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "Days"
        case .week: "Weeks"
        case .month: "Months"
        case .year: "Years"
        }
    }
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

struct PeriodKey: Hashable, Comparable, Identifiable, Sendable {
    var unit: PeriodUnit
    var start: Date
    var id: String { "\(unit.rawValue)-\(start.timeIntervalSinceReferenceDate)" }

    static func < (lhs: PeriodKey, rhs: PeriodKey) -> Bool { lhs.start < rhs.start }

    func interval(calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: unit.component, for: start)
    }

    func year(calendar: Calendar = .current) -> Int { calendar.component(.year, from: start) }

    private func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
    }

    /// Full title, for decks and ranked lists.
    func title(calendar: Calendar = .current) -> String {
        let style = style(calendar)
        switch unit {
        case .day: return start.formatted(style.weekday(.abbreviated).month(.abbreviated).day().year())
        case .week: return "Week of " + start.formatted(style.month(.abbreviated).day().year())
        case .month: return start.formatted(style.month(.wide).year())
        case .year: return start.formatted(style.year())
        }
    }

    /// Title inside a year section, where the year is already shown.
    func shortTitle(calendar: Calendar = .current) -> String {
        let style = style(calendar)
        switch unit {
        case .day: return start.formatted(style.weekday(.abbreviated).month(.abbreviated).day())
        case .week: return "Week of " + start.formatted(style.month(.abbreviated).day())
        case .month: return start.formatted(style.month(.wide))
        case .year: return title(calendar: calendar)
        }
    }

    /// Smallest label, for grid tiles.
    func tileTitle(calendar: Calendar = .current) -> String {
        let style = style(calendar)
        switch unit {
        case .day, .week: return start.formatted(style.month(.abbreviated).day())
        case .month: return start.formatted(style.month(.abbreviated))
        case .year: return title(calendar: calendar)
        }
    }
}

enum LookbackLayout: String, CaseIterable, Identifiable {
    case list, grid, cards
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        case .cards: "Cards"
        }
    }
    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.3x3"
        case .cards: "rectangle.grid.1x2"
        }
    }
}

enum LookbackSort: String, CaseIterable, Identifiable {
    case newest, oldest, mostPhotos, mostLeft
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .mostPhotos: "Most photos"
        case .mostLeft: "Most left to review"
        }
    }
}

struct PeriodEntry: Identifiable, Equatable {
    var key: PeriodKey
    var count: Int
    var reviewed: Int
    /// A few of the newest photos; the first one stored on this iPhone is the cover.
    var coverIDs: [String]

    var id: PeriodKey { key }
    var left: Int { max(count - reviewed, 0) }
    var isDone: Bool { count > 0 && left == 0 }
    var progress: Double { count == 0 ? 0 : Double(min(reviewed, count)) / Double(count) }
}

enum PeriodGrouping {
    static let coverCandidates = 4

    struct Section: Identifiable, Equatable {
        var year: Int?
        var entries: [PeriodEntry]
        var id: Int { year ?? -1 }
    }

    /// Photo IDs per period, each list newest first. `index` must be newest first.
    static func group(_ index: [AssetStamp], by unit: PeriodUnit,
                      calendar: Calendar = .current) -> [PeriodKey: [String]] {
        var groups: [PeriodKey: [String]] = [:]
        var current: (interval: DateInterval, key: PeriodKey)?
        for stamp in index {
            // Neighbouring photos usually share a period; skip the calendar lookup then.
            if let current, stamp.date >= current.interval.start, stamp.date < current.interval.end {
                groups[current.key, default: []].append(stamp.id)
                continue
            }
            guard let interval = calendar.dateInterval(of: unit.component, for: stamp.date) else { continue }
            let key = PeriodKey(unit: unit, start: interval.start)
            groups[key, default: []].append(stamp.id)
            current = (interval, key)
        }
        return groups
    }

    static func entries(_ groups: [PeriodKey: [String]], decided: Set<String>, sort: LookbackSort,
                        hideDone: Bool) -> [PeriodEntry] {
        var entries = groups.map { key, ids in
            PeriodEntry(key: key, count: ids.count,
                        reviewed: ids.reduce(0) { $0 + (decided.contains($1) ? 1 : 0) },
                        coverIDs: Array(ids.prefix(coverCandidates)))
        }
        if hideDone { entries.removeAll(where: \.isDone) }
        switch sort {
        case .newest: entries.sort { $0.key > $1.key }
        case .oldest: entries.sort { $0.key < $1.key }
        case .mostPhotos: entries.sort { $0.count == $1.count ? $0.key > $1.key : $0.count > $1.count }
        case .mostLeft: entries.sort { $0.left == $1.left ? $0.key > $1.key : $0.left > $1.left }
        }
        return entries
    }

    /// Date sorts group days, weeks and months by year; years and ranked sorts are one list.
    static func sections(_ entries: [PeriodEntry], unit: PeriodUnit, sort: LookbackSort,
                         calendar: Calendar = .current) -> [Section] {
        let byYear = unit != .year && (sort == .newest || sort == .oldest)
        guard byYear else { return entries.isEmpty ? [] : [Section(year: nil, entries: entries)] }
        var sections: [Section] = []
        for entry in entries {
            let year = entry.key.year(calendar: calendar)
            if sections.last?.year == year {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append(Section(year: year, entries: [entry]))
            }
        }
        return sections
    }
}
