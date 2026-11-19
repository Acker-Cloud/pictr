import SwiftUI

/// Home: photos taken on today's date in earlier years.
struct TodayView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(DecisionsModel.self) private var decisions
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [ReviewItem]?
    @State private var showsShuffle = false
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var thumbnails = ThumbnailProvider()
    @Environment(\.displayScale) private var displayScale
    @AppStorage(Prefs.dailyGoal) private var dailyGoal = 50
    @AppStorage(Prefs.batchSize) private var batchSize = 0
    @AppStorage(Prefs.rangeKey) private var range: OnThisDayRange = .day

    private struct YearGroup: Identifiable {
        var yearsAgo: Int
        var items: [ReviewItem]
        var id: Int { yearsAgo }
    }

    private var undecided: [ReviewItem] {
        (items ?? []).filter { decisions.book.decision(for: $0.id) == nil }
    }

    private var years: [YearGroup] {
        Dictionary(grouping: items ?? []) { OnThisDay.yearsAgo($0.creationDate, from: day) ?? 0 }
            .map { YearGroup(yearsAgo: $0.key, items: $0.value) }
            .sorted { $0.yearsAgo < $1.yearsAgo }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.x8) {
                    header
                    if items == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Space.x12)
                    } else if items?.isEmpty == true {
                        empty
                        shuffleCard
                    } else {
                        hero
                        yearStrip
                        shuffleCard
                    }
                }
                .padding(.horizontal, Theme.Space.x5)
                .padding(.bottom, Theme.Space.x12)
            }
            .background(PictrBackground())
            .refreshable { await load() }
            .task { if items == nil { await load() } }
            .onChange(of: scenePhase) { _, phase in
                // Resumed on a later day: show that day, not the one Pictr was left on.
                if phase == .active, Calendar.current.startOfDay(for: .now) != day { Task { await load() } }
            }
            .onChange(of: range) { Task { await load() } }
            .onChange(of: router.pendingShuffle, initial: true) { _, pending in
                guard pending else { return }
                router.pendingShuffle = false
                showsShuffle = true
            }
            .navigationDestination(isPresented: $showsShuffle) { shuffleDeck }
            .pageHeader(day.formatted(.dateTime.month(.wide).day()),
                        accessibilityTitle: "On this day, \(day.formatted(.dateTime.month(.wide).day()))")
        }
    }

    private var header: some View {
        habit
            .padding(.top, Theme.Space.x1)
    }

    /// Pills: what this date holds, then the GetSorted-style habit loop.
    private var habit: some View {
        let streak = decisions.book.streak(endingOn: .now)
        let todayCount = decisions.book.reviewedCount(on: .now)
        return ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: Theme.Space.x2) {
                HStack(spacing: Theme.Space.x2) {
                    if let photos = photosPill {
                        Label(photos, systemImage: "photo.on.rectangle")
                            .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x2)
                            .glassEffect()
                    }

                    Label {
                        Text(streak == 0 ? "Start a streak" : streak == 1 ? "1-day streak" : "\(streak)-day streak")
                    } icon: {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(streak > 0 ? Theme.Palette.accent : Theme.Palette.textSecondary)
                    }
                    .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x2)
                    .glassEffect()

                    Label("\(todayCount) of \(dailyGoal) today",
                          systemImage: todayCount >= dailyGoal ? "checkmark.circle.fill" : "checkmark")
                        .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x2)
                        .glassEffect()
                }
                .font(Theme.Typeface.captionMedium)
                .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .scrollClipDisabled()
        .contentTransition(.numericText())
    }

    /// A fanned stack of the next photos with the call to action in glass.
    private var hero: some View {
        let preview = Array((undecided.isEmpty ? items ?? [] : undecided).prefix(3))
        return ZStack(alignment: .bottom) {
            ZStack {
                ForEach(Array(preview.enumerated().reversed()), id: \.element.id) { index, item in
                    Thumb(id: item.id, provider: thumbnails, pixels: 600 * displayScale)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(.white.opacity(0.08)))
                        .rotationEffect(.degrees(Double(index) * (index % 2 == 0 ? 4 : -4)))
                        .scaleEffect(1 - CGFloat(index) * 0.05)
                        .offset(y: -CGFloat(index) * 14)
                        .shadow(color: index == 0 ? Theme.Palette.accent.opacity(0.35) : .black.opacity(0.45),
                                radius: index == 0 ? 30 : 18, y: 10)
                }
            }
            .padding(.top, Theme.Space.x6)

            if undecided.isEmpty {
                Label("All reviewed for today", systemImage: "checkmark")
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Space.x5).padding(.vertical, Theme.Space.x3)
                    .glassEffect()
                    .padding(Theme.Space.x5)
            } else {
                NavigationLink {
                    DeckView(title: range == .week ? "This week" : "On this day",
                             items: batchSize > 0 ? Array(undecided.prefix(batchSize)) : undecided,
                             today: day)
                } label: {
                    Label("Review \(batchSize > 0 ? min(batchSize, undecided.count) : undecided.count)", systemImage: "rectangle.stack.fill")
                        .padding(.horizontal, Theme.Space.x3)
                }
                .primaryGlassButton()
                .padding(Theme.Space.x5)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var yearStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x3) {
            Eyebrow("By year")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.x3) {
                    ForEach(years) { group in
                        NavigationLink {
                            DeckView(title: yearTitle(group.yearsAgo),
                                     items: group.items.filter { decisions.book.decision(for: $0.id) == nil },
                                     today: day)
                        } label: {
                            YearTile(title: yearTitle(group.yearsAgo), count: group.items.count,
                                     coverID: group.items.first?.id, provider: thumbnails,
                                     pixels: 300 * displayScale)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x4) {
            PictrMark(size: 96)
            Text(range == .day
                 ? "Nothing from this date yet. Look at the whole week, open Lookback, or check back tomorrow."
                 : "Nothing from this week yet. Open Lookback to sweep your library, or check back tomorrow.")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            if range == .day {
                Button { range = .week } label: {
                    Label("Show this week", systemImage: "calendar")
                }
                .secondaryGlassButton()
            }
        }
        .padding(.top, Theme.Space.x8)
    }

    /// A random deck from any year, for days when the date has little to show.
    private var shuffleCard: some View {
        Panel {
            HStack(spacing: Theme.Space.x4) {
                IconTile(systemName: "shuffle", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shuffle")
                        .font(Theme.Typeface.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("\(shuffleCount) random photos you haven't reviewed, from any year.")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Button { showsShuffle = true } label: {
                    Text("Start")
                }
                .secondaryGlassButton()
                .accessibilityLabel("Start Shuffle")
            }
        }
    }

    private var shuffleCount: Int { batchSize > 0 ? batchSize : Shuffle.defaultCount }

    private var shuffleDeck: some View {
        let client = library.client
        let decided = decisions.book.decidedIDs
        let count = shuffleCount
        return DeckLoaderView(title: "Shuffle", load: {
            let ids = Shuffle.pick(client.assetIndex().map(\.id), excluding: decided, count: count)
            return client.reviewItems(ids: ids)
        }, showsQuickSelect: false)
    }

    private func yearTitle(_ yearsAgo: Int) -> String {
        yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago"
    }

    private var photosPill: String? {
        guard let items, !items.isEmpty else { return nil }
        let photos = items.count == 1 ? "1 photo" : "\(items.count) photos"
        let span = years.count == 1 ? "1 year" : "\(years.count) years"
        return range == .week ? "\(photos) this week · \(span)" : "\(photos) · \(span)"
    }

    private func load() async {
        day = Calendar.current.startOfDay(for: .now)
        let client = library.client
        let today = day
        let range = range
        items = await Task.detached(priority: .userInitiated) {
            guard let earliest = client.earliestAssetDate() else { return [ReviewItem]() }
            let windows = OnThisDay.windows(on: today, earliestYear: Calendar.current.component(.year, from: earliest),
                                            range: range)
            // Newest year first, chronological within a day.
            return client.reviewItems(in: windows).sorted {
                let l = $0.creationDate ?? .distantPast, r = $1.creationDate ?? .distantPast
                let ly = Calendar.current.component(.year, from: l), ry = Calendar.current.component(.year, from: r)
                return ly == ry ? l < r : ly > ry
            }
        }.value
    }
}

private struct YearTile: View {
    let title: String
    let count: Int
    let coverID: String?
    let provider: ThumbnailProvider
    let pixels: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let coverID {
                Thumb(id: coverID, provider: provider, pixels: pixels)
            } else {
                Theme.Palette.surface
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.Typeface.captionMedium)
                Text("\(count)").font(Theme.Typeface.number)
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x2)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .padding(Theme.Space.x2)
        }
        .frame(width: 140, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .accessibilityElement(children: .combine)
    }
}

/// A local-only thumbnail that fills its frame.
struct Thumb: View {
    let id: String
    let provider: ThumbnailProvider
    let pixels: CGFloat
    @State private var thumbnail: Thumbnail?

    var body: some View {
        Color.clear
            .overlay {
                if let image = thumbnail?.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        // Fill overflows the frame; only the visible frame takes touches.
                        .allowsHitTesting(false)
                } else {
                    Theme.Palette.surface
                        .overlay {
                            if thumbnail?.isInCloud == true {
                                Image(systemName: "icloud").foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: id) {
                thumbnail = await provider.thumbnail(for: id, targetSize: CGSize(width: pixels, height: pixels))
            }
    }
}
