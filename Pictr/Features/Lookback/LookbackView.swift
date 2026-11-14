import SwiftUI
import UIKit

/// Lookback: the whole library by day, week, month or year, as a list, grid or
/// cards, sorted by date, size or what's left to review.
struct LookbackView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(DecisionsModel.self) private var decisions
    @Environment(\.displayScale) private var displayScale
    @State private var index: [AssetStamp]?
    @State private var groups: [PeriodKey: [String]] = [:]
    @State private var thumbnails = ThumbnailProvider()
    @AppStorage("lookback.unit") private var unit: PeriodUnit = .month
    @AppStorage("months.layout") private var layout: LookbackLayout = .list
    @AppStorage("months.sort") private var sort: LookbackSort = .newest
    @AppStorage("months.hideDone") private var hideDone = false

    private var entries: [PeriodEntry] {
        PeriodGrouping.entries(groups, decided: decisions.book.decidedIDs, sort: sort, hideDone: hideDone)
    }
    private var sections: [PeriodGrouping.Section] { PeriodGrouping.sections(entries, unit: unit, sort: sort) }

    var body: some View {
        NavigationStack {
            Group {
                if index == nil {
                    ProgressView("Indexing your library")
                        .font(Theme.Typeface.callout)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    ContentUnavailableView(hideDone ? "Everything is sorted" : "No photos",
                                           systemImage: hideDone ? "checkmark.circle" : "photo",
                                           description: Text(hideDone ? "Turn off Hide finished to see them." : ""))
                } else {
                    switch layout {
                    case .list: listLayout
                    case .grid: gridLayout
                    case .cards: cardsLayout
                    }
                }
            }
            .background(PictrBackground())
            .pageHeader("Lookback") { optionsMenu }
            .task {
                guard index == nil else { return }
                let cache = AssetIndexCache()
                if let cached = await Task.detached(priority: .userInitiated, operation: { cache.load() }).value {
                    await apply(cached)
                }
                await load()
            }
            .onChange(of: unit) { Task { await regroup() } }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Group by", selection: $unit) {
                ForEach(PeriodUnit.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("View", selection: $layout) {
                ForEach(LookbackLayout.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Sort", selection: $sort) {
                ForEach(LookbackSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Toggle("Hide finished", systemImage: "checkmark.circle", isOn: $hideDone)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("View options")
    }

    // MARK: Layouts

    private var listLayout: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        link(entry) { PeriodRow(entry: entry, showsYear: section.year == nil,
                                                provider: thumbnails, pixels: 112 * displayScale) }
                            .listRowBackground(GlassRow())
                    }
                } header: {
                    if let year = section.year { yearHeader(year) }
                }
            }
        }
        .pictrList()
        .refreshable { await load() }
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.x6) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: Theme.Space.x3) {
                        if let year = section.year { yearHeader(year) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Space.x2)],
                                  spacing: Theme.Space.x2) {
                            ForEach(section.entries) { entry in
                                link(entry) { PeriodTile(entry: entry, showsYear: section.year == nil,
                                                         provider: thumbnails, pixels: 220 * displayScale) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.x4)
            .padding(.bottom, Theme.Space.x12)
        }
        .refreshable { await load() }
    }

    private var cardsLayout: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.x4) {
                ForEach(sections) { section in
                    if let year = section.year { yearHeader(year).padding(.top, Theme.Space.x2) }
                    ForEach(section.entries) { entry in
                        link(entry) { PeriodCard(entry: entry, provider: thumbnails, pixels: 440 * displayScale) }
                            .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, Theme.Space.x4)
            .padding(.bottom, Theme.Space.x12)
        }
        .refreshable { await load() }
    }

    private func yearHeader(_ year: Int) -> some View {
        SectionLabel(String(year))
    }

    private func link(_ entry: PeriodEntry, @ViewBuilder label: () -> some View) -> some View {
        NavigationLink {
            DeckLoaderView(title: entry.key.title(), load: loader(for: entry.key))
        } label: {
            label()
        }
    }

    private func loader(for key: PeriodKey) -> @Sendable () -> [ReviewItem] {
        let client = library.client
        return {
            guard let interval = key.interval() else { return [] }
            return client.reviewItems(in: [interval])
        }
    }

    private func load() async {
        let client = library.client
        let fresh = await Task.detached(priority: .userInitiated) {
            let index = client.assetIndex()
            AssetIndexCache().save(index)
            return index
        }.value
        await apply(fresh)
    }

    private func apply(_ fresh: [AssetStamp]) async {
        index = fresh
        await regroup()
    }

    private func regroup() async {
        guard let index else { return }
        let unit = unit
        groups = await Task.detached(priority: .userInitiated) { PeriodGrouping.group(index, by: unit) }.value
    }
}

private struct PeriodRow: View {
    let entry: PeriodEntry
    let showsYear: Bool
    let provider: ThumbnailProvider
    let pixels: CGFloat

    var body: some View {
        HStack(spacing: Theme.Space.x3) {
            Cover(ids: entry.coverIDs, provider: provider, pixels: pixels)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            VStack(alignment: .leading, spacing: Theme.Space.x1) {
                HStack {
                    Text(showsYear ? entry.key.title() : entry.key.shortTitle())
                        .font(Theme.Typeface.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    if entry.isDone {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.Palette.accent)
                            .accessibilityLabel("Done")
                    }
                    Text("\(entry.reviewed)/\(entry.count)")
                        .font(Theme.Typeface.number)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                ProgressBar(value: entry.progress)
            }
        }
        .padding(.vertical, Theme.Space.x1)
        .accessibilityElement(children: .combine)
    }
}

/// Square cover with the period over a dark fade.
private struct PeriodTile: View {
    let entry: PeriodEntry
    let showsYear: Bool
    let provider: ThumbnailProvider
    let pixels: CGFloat

    var body: some View {
        Cover(ids: entry.coverIDs, provider: provider, pixels: pixels)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.key.tileTitle() + (showsYear && entry.key.unit != .year ? " \(entry.key.year())" : ""))
                        .font(Theme.Typeface.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(entry.isDone ? "Done" : "\(entry.left) left")
                        .font(Theme.Typeface.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.x2).padding(.vertical, 6)
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(6)
            }
            .overlay(alignment: .bottom) {
                if !entry.isDone {
                    GeometryReader { geo in
                        Rectangle().fill(Theme.Palette.accent)
                            .frame(width: geo.size.width * entry.progress, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if entry.isDone {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.Palette.accent)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .emberStroke(radius: Theme.Radius.lg)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.key.title())
            .accessibilityValue(entry.isDone ? "Done, \(entry.count) photos" : "\(entry.left) of \(entry.count) left")
    }
}

/// Wide cover card for browsing by picture.
private struct PeriodCard: View {
    let entry: PeriodEntry
    let provider: ThumbnailProvider
    let pixels: CGFloat

    var body: some View {
        Cover(ids: entry.coverIDs, provider: provider, pixels: pixels)
            .frame(height: 190)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Theme.Space.x2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.key.title())
                            .font(Theme.Typeface.title3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Text(entry.isDone ? "\(entry.count) photos" : "\(entry.left) of \(entry.count) left")
                            .font(Theme.Typeface.captionMedium)
                    }
                    if !entry.isDone {
                        ProgressBar(value: entry.progress)
                    }
                }
                .foregroundStyle(.white)
                .padding(Theme.Space.x3)
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(Theme.Space.x2)
            }
            .overlay(alignment: .topTrailing) {
                if entry.isDone {
                    Label("Done", systemImage: "checkmark.seal.fill")
                        .font(Theme.Typeface.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x2)
                        .glassEffect(.regular.tint(Theme.Palette.accent.opacity(0.6)))
                        .padding(Theme.Space.x3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .emberStroke(radius: Theme.Radius.card)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.key.title())
            .accessibilityValue(entry.isDone ? "Done, \(entry.count) photos" : "\(entry.left) of \(entry.count) left")
    }
}

/// Thin red-on-grey progress line.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.borderStrong)
                Capsule().fill(Theme.Palette.accent)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
