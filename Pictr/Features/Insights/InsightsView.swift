import Charts
import SwiftUI

/// What takes space in the Cleanup window: kinds, years, the largest items and where
/// the files live. Sizes marked "est." include estimates.
struct InsightsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ViewerPresenter.self) private var viewer
    @Environment(\.displayScale) private var displayScale
    @State private var insights: LibraryInsights?
    @State private var thumbnails = ThumbnailProvider()

    var body: some View {
        List {
            if let insights {
                if insights.count == 0 {
                    Text("Nothing in the Cleanup window yet. Change Look back in Settings to include more.")
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .listRowBackground(GlassRow())
                } else {
                    content(insights)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .font(Theme.Typeface.body)
        .pictrList()
        .navigationTitle("What's taking space")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .settingsToolbar()
        .task(id: library.phase == .ready) { insights = await library.insights() }
    }

    @ViewBuilder private func content(_ insights: LibraryInsights) -> some View {
        Group {
            Section { summary(insights) }

            Section {
                ForEach(insights.kinds) { slice in
                    KindRow(slice: slice, total: insights.bytes)
                }
            } header: {
                SectionLabel("By kind")
            }

            if !insights.years.isEmpty {
                Section {
                    yearChart(insights)
                } header: {
                    SectionLabel("By year")
                } footer: {
                    let notes = [
                        insights.undatedBytes > 0 ? "Plus \(ByteFormat.string(insights.undatedBytes)) with no capture date." : nil,
                        insights.years.contains(where: \.hasEstimates) ? "Some sizes are estimates." : nil,
                    ].compactMap { $0 }
                    if !notes.isEmpty { Text(notes.joined(separator: " ")) }
                }
            }

            Section {
                ForEach(insights.largest) { item in
                    Button {
                        viewer.open(insights.largest.map(\.id), at: insights.largest.firstIndex(of: item) ?? 0)
                    } label: {
                        LargestRow(item: item, provider: thumbnails, pixels: 112 * displayScale)
                    }
                }
            } header: {
                SectionLabel("Largest")
            } footer: {
                Text("Tap to look closer. Add anything you don't need to Ready to Delete from there.")
            }

            Section {
                StorageRow(title: "On this iPhone", bytes: insights.onDeviceBytes)
                StorageRow(title: "Only in iCloud", bytes: insights.cloudOnlyBytes)
                if insights.unknownBytes > 0 {
                    StorageRow(title: "Not reported", bytes: insights.unknownBytes)
                }
            } header: {
                SectionLabel("Where it's stored")
            } footer: {
                Text("Deleting an iCloud-only photo gives back iCloud space, not space on this iPhone. Deleted items wait in Recently Deleted for 30 days.")
            }
        }
        .listRowBackground(GlassRow())
    }

    private func summary(_ insights: LibraryInsights) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.x1) {
            Eyebrow(windowLabel(library.settings.windowDays))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteFormat.string(insights.bytes))
                    .font(Theme.Typeface.hero)
                    .kerning(-1)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if insights.hasEstimates { EstimatedMarker() }
            }
            Text(insights.count == 1 ? "1 item" : "\(insights.count.formatted()) items")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.vertical, Theme.Space.x2)
        .accessibilityElement(children: .combine)
    }

    private func yearChart(_ insights: LibraryInsights) -> some View {
        // Every year from the first to the last, so an empty year shows as a gap rather than vanishing,
        // and about six labels, always including the newest year.
        let bytesByYear = Dictionary(uniqueKeysWithValues: insights.years.map { ($0.year, $0.bytes) })
        let years = insights.years.first.flatMap { first in insights.years.last.map { Array(first.year...$0.year) } } ?? []
        let step = max(1, (years.count + 5) / 6)
        let labelled = years.enumerated().filter { (years.count - 1 - $0.offset) % step == 0 }.map { String($0.element) }
        return Chart(years, id: \.self) { year in
            BarMark(x: .value("Year", String(year)), y: .value("Bytes", Double(bytesByYear[year] ?? 0)))
                .foregroundStyle(Theme.Palette.accent)
                .cornerRadius(Theme.Radius.sm)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.Palette.border)
                AxisValueLabel {
                    if let bytes = value.as(Double.self) { Text(ByteFormat.string(Int64(bytes))) }
                }
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let year = value.as(String.self), labelled.contains(year) { Text(year) }
                }
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(height: 180)
        .padding(.vertical, Theme.Space.x2)
        .accessibilityLabel("Space by capture year")
        .accessibilityValue(insights.years.map { "\($0.year): \(ByteFormat.string($0.bytes))" }.joined(separator: ", "))
    }
}

private struct KindRow: View {
    let slice: LibraryInsights.Slice
    let total: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x2) {
            HStack {
                RowLabel(slice.kind.title, systemImage: slice.kind.systemImage)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(ByteFormat.string(slice.bytes) + (slice.hasEstimates ? " est." : ""))
                        .font(Theme.Typeface.number)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(slice.count.formatted())
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            ProgressBar(value: total > 0 ? Double(slice.bytes) / Double(total) : 0)
        }
        .padding(.vertical, Theme.Space.x1)
        .accessibilityElement(children: .combine)
    }
}

private struct LargestRow: View {
    let item: LibraryInsights.Item
    let provider: ThumbnailProvider
    let pixels: CGFloat

    var body: some View {
        HStack(spacing: Theme.Space.x3) {
            Thumb(id: item.id, provider: provider, pixels: pixels)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title)
                    .font(Theme.Typeface.bodyMedium)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let date = item.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
            Text(ByteFormat.string(item.bytes) + (item.isEstimated ? " est." : ""))
                .font(Theme.Typeface.number)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the item")
    }
}

private struct StorageRow: View {
    let title: String
    let bytes: Int64

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(ByteFormat.string(bytes))
                .font(Theme.Typeface.number)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
