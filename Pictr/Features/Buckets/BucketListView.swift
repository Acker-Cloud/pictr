import SwiftUI

struct BucketListView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(DecisionsModel.self) private var decisions

    private var buckets: BucketSet { model.buckets.excluding(decisions.book.decidedIDs, queued: decisions.book.queuedIDs) }
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnails = ThumbnailProvider()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.x5) {
                    if model.authState == .limited {
                        Panel { LimitedAccessBanner() }
                    }

                    Panel { header }

                    NavigationLink {
                        InsightsView()
                    } label: {
                        Panel {
                            HStack(spacing: Theme.Space.x3) {
                                IconTile(systemName: "chart.pie.fill", size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("What's taking space")
                                        .font(Theme.Typeface.headline)
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Text("By kind and year, the largest items, and what's only in iCloud.")
                                        .font(Theme.Typeface.caption)
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("insights-link")

                    if case let .scanning(progress) = model.phase {
                        Panel {
                            VStack(alignment: .leading, spacing: Theme.Space.x2) {
                                Text("Measuring \(progress.completed) of \(progress.total)")
                                    .font(Theme.Typeface.callout)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                ProgressBar(value: progress.fraction)
                            }
                        }
                    }

                    Panel { AnalysisPanel() }

                    SectionLabel("Suggestions")
                        .padding(.top, Theme.Space.x2)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.x3),
                                        GridItem(.flexible(), spacing: Theme.Space.x3)],
                              spacing: Theme.Space.x3) {
                        ForEach(buckets.buckets) { bucket in
                            NavigationLink(value: bucket.kind) {
                                BucketTile(bucket: bucket,
                                           awaitingAnalysis: bucket.kind.needsAnalysis && model.analyzedCount == 0,
                                           provider: thumbnails, pixels: 240 * displayScale)
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(bucket.count == 0)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.x4)
                .padding(.bottom, Theme.Space.x12)
            }
            .background(PictrBackground())
            .pageHeader("Cleanup")
            .navigationDestination(for: BucketKind.self) { kind in
                if kind == .similar || kind == .duplicates {
                    SimilarDetailView(kind: kind)
                } else {
                    BucketDetailView(kind: kind)
                }
            }
            .refreshable { await model.scan() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refreshAccess() } }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x1) {
            Eyebrow("Reclaimable")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteFormat.string(buckets.reclaimableBytes))
                    .font(Theme.Typeface.hero)
                    .kerning(-1)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                if buckets.reclaimableHasEstimates {
                    EstimatedMarker()
                }
            }
            Text("\(windowLabel(model.settings.windowDays)), each item counted once.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

func windowLabel(_ days: Int) -> String {
    switch days {
    case 0: "Whole library"
    case 365: "Last year"
    default: "Last \(days) days"
    }
}

/// A suggestion as a photo tile: its first photo under a dark fade, red icon,
/// name, count and size.
struct BucketTile: View {
    let bucket: Bucket
    var awaitingAnalysis = false
    let provider: ThumbnailProvider
    let pixels: CGFloat

    private var subtitle: String {
        if awaitingAnalysis { return "Run analysis" }
        if bucket.count == 0 { return "Nothing found" }
        return bucket.count == 1 ? "1 item" : "\(bucket.count) items"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if !bucket.members.isEmpty {
                Cover(ids: bucket.members.prefix(PeriodGrouping.coverCandidates).map(\.id),
                      provider: provider, pixels: pixels)
            } else {
                Rectangle().fill(.clear)
                    .glassEffect(.regular.tint(Theme.Palette.accent.opacity(0.08)), in: Rectangle())
            }
            IconTile(systemName: bucket.kind.systemImage, size: 30)
                .padding(Theme.Space.x3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.kind.title)
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    Text(subtitle)
                    if bucket.count > 0 {
                        Text("·")
                        Text(ByteFormat.string(bucket.totalBytes))
                        if bucket.hasEstimates { Text("est.") }
                    }
                }
                .font(Theme.Typeface.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(Theme.Space.x2)
        }
        .aspectRatio(1.15, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card - 8))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card - 8))
        .emberStroke(radius: Theme.Radius.card - 8)
        .opacity(bucket.count == 0 ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bucket.kind.title)
        .accessibilityValue(bucket.count == 0 ? subtitle : "\(subtitle), \(ByteFormat.string(bucket.totalBytes))")
        .accessibilityAddTraits(.isButton)
    }
}

/// Marks a number that includes estimated sizes.
struct EstimatedMarker: View {
    var body: some View {
        Text("est.")
            .font(Theme.Typeface.eyebrow)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .foregroundStyle(Theme.Palette.textSecondary)
            .accessibilityLabel("estimated")
    }
}
