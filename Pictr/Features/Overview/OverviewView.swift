import Charts
import SwiftUI
import UniformTypeIdentifiers

enum Prefs {
    static let dailyGoal = "dailyGoal"
    /// Photos per deck; 0 means the whole month or day.
    static let batchSize = "batchSize"
    static let dailyGoals = [25, 50, 100, 200]
    static let batchSizes = [25, 50, 100, 0]
    static let planTargets: [Int64] = [100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000]

    static let rangeKey = "onThisDay.range"

    static func batchLabel(_ size: Int) -> String { size == 0 ? "All photos" : "\(size) photos" }

    /// The saved On This Day range, for code outside a view.
    static var onThisDayRange: OnThisDayRange {
        UserDefaults.standard.string(forKey: rangeKey).flatMap(OnThisDayRange.init(rawValue:)) ?? .day
    }
}

/// Progress: today against the daily goal, the last two weeks, totals,
/// the Cleanup Plan, achievements and cleanup history.
struct OverviewView: View {
    @Environment(DecisionsModel.self) private var decisions
    @AppStorage(Prefs.dailyGoal) private var dailyGoal = 50

    private var book: DecisionBook { decisions.book }
    private var stats: ProgressStats { book.stats() }

    var body: some View {
        List {
            Group {
                Section { today }
                Section { chart } header: { SectionLabel("Last 14 days") }
                Section { totals } header: { SectionLabel("Totals") }
                Section {
                    plan
                } header: {
                    SectionLabel("Cleanup Plan")
                } footer: {
                    Text("Counts what you confirm from Ready to Delete. Photos stay in Recently Deleted for 30 days before the space comes back.")
                }
                Section {
                    ForEach(Achievement.allCases) { AchievementRow(achievement: $0, progress: $0.progress(stats)) }
                } header: {
                    SectionLabel("Achievements")
                }
                Section {
                    history
                    if !book.applied.isEmpty {
                        ShareLink(item: HistoryExport(csv: book.historyCSV()),
                                  preview: SharePreview("Pictr cleanup history")) {
                            RowLabel("Export history as CSV", systemImage: "square.and.arrow.up")
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                    }
                } header: {
                    SectionLabel("History")
                }
            }
            .listRowBackground(GlassRow())
        }
        .font(Theme.Typeface.body)
        .pictrList()
        .navigationTitle("Progress")
    }

    private var today: some View {
        let done = book.reviewedCount(on: .now)
        let fraction = min(Double(done) / Double(max(dailyGoal, 1)), 1)
        return HStack(spacing: Theme.Space.x5) {
            ZStack {
                Circle().stroke(Theme.Palette.borderStrong, lineWidth: 8)
                Circle().trim(from: 0, to: fraction)
                    .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.Palette.accent.opacity(0.6), radius: 8)
                Image(systemName: done >= dailyGoal ? "checkmark" : "flame.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.x1) {
                Eyebrow("Today")
                Text("\(done) of \(dailyGoal)")
                    .font(Theme.Typeface.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                Text("Streak \(stats.streak) · Best \(stats.bestStreak)")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.vertical, Theme.Space.x2)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let days = book.recentDays(14)
        return Chart(days) { day in
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Reviewed", day.count))
                .foregroundStyle(Theme.Palette.accent)
                .cornerRadius(Theme.Radius.sm)
            RuleMark(y: .value("Goal", dailyGoal))
                .foregroundStyle(Theme.Palette.textSecondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.Palette.border)
                AxisValueLabel().foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(height: 160)
        .padding(.vertical, Theme.Space.x2)
        .accessibilityLabel("Photos reviewed per day, last 14 days")
        .accessibilityValue(days.map { "\($0.date.formatted(.dateTime.month().day())): \($0.count)" }.joined(separator: ", "))
    }

    @ViewBuilder private var totals: some View {
        StatRow(title: "Reviewed", value: stats.reviewed.formatted())
        StatRow(title: "Kept", value: stats.kept.formatted())
        StatRow(title: "In Ready to Delete", value: stats.queued.formatted())
        StatRow(title: "Moved to Recently Deleted",
                value: "\(stats.movedCount.formatted()) · \(ByteFormat.string(stats.movedBytes))")
    }

    @ViewBuilder private var plan: some View {
        if let plan = book.plan {
            let progress = book.planProgress
            VStack(alignment: .leading, spacing: Theme.Space.x2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteFormat.string(progress))
                        .font(Theme.Typeface.title3)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("of \(ByteFormat.string(plan.targetBytes))")
                        .font(Theme.Typeface.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    if progress >= plan.targetBytes {
                        Label("Reached", systemImage: "checkmark")
                            .font(Theme.Typeface.captionMedium)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                ProgressBar(value: Double(progress) / Double(max(plan.targetBytes, 1)))
                Text("Since \(plan.startedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.vertical, Theme.Space.x1)
            .accessibilityElement(children: .combine)
            Button("End plan") { decisions.endPlan() }
        } else {
            Menu {
                ForEach(Prefs.planTargets, id: \.self) { target in
                    Button(ByteFormat.string(target)) { decisions.startPlan(targetBytes: target) }
                }
            } label: {
                Label("Start a plan", systemImage: "target")
            }
        }
    }

    @ViewBuilder private var history: some View {
        if book.applied.isEmpty {
            Text("Confirmed deletes from Ready to Delete appear here.")
                .font(Theme.Typeface.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
        } else {
            ForEach(book.applied.reversed(), id: \.date) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.count == 1 ? "1 item" : "\(entry.count) items")
                            .font(Theme.Typeface.bodyMedium)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Text(ByteFormat.string(entry.bytes))
                        .font(Theme.Typeface.number)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Cleanup history as a CSV file, written when the share sheet asks for it.
private struct HistoryExport: Transferable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: "Pictr cleanup history.csv")
            try Data(export.csv.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

private struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typeface.number)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementRow: View {
    let achievement: Achievement
    let progress: Achievement.Progress

    var body: some View {
        HStack(spacing: Theme.Space.x3) {
            Group {
                if progress.unlocked {
                    IconTile(systemName: achievement.systemImage, size: 44)
                } else {
                    Image(systemName: achievement.systemImage)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 44 * 0.26))
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.x1) {
                Text(achievement.title)
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(progress.unlocked ? achievement.detail : "\(achievement.detail) · \(progress.label)")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if !progress.unlocked {
                    ProgressBar(value: progress.fraction)
                }
            }
            Spacer()
            if progress.unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Theme.Space.x1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress.unlocked ? "Unlocked" : progress.label)
    }
}
