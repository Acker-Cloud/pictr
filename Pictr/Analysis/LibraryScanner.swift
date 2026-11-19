import Foundation
import Vision

struct ScanProgress: Sendable, Equatable {
    var completed: Int
    var total: Int

    var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }
}

/// Owns the sized asset set off the main actor and turns it into buckets.
actor LibraryScanner {
    static let windowDays = 30

    private let client: any PhotoLibraryClient
    private let sizer: any SizeProvider
    private let analyzer = VisionAnalyzer()
    private var assets: [String: ScannedAsset] = [:]
    private var analysis: [String: AssetAnalysis] = [:]
    private var prints: [String: FeaturePrintObservation] = [:]
    private var similar: [[String]] = []
    private var settings = BucketSettings()
    private var maybeDelete: [(id: String, reason: String)] = []
    private(set) var taste = TasteModel.prior
    private let traitsURL: URL?
    private var traits: TraitStore
    /// Most decided photos read per learning pass, so one pass stays a few minutes at most.
    static let learnLimit = 2_000

    static let suggestionThreshold = 0.6
    static let suggestionLimit = 300

    init(client: any PhotoLibraryClient, sizer: any SizeProvider = .standard, traitsURL: URL? = nil) {
        self.client = client
        self.sizer = sizer
        self.traitsURL = traitsURL
        self.traits = TraitStore.load(from: traitsURL)
    }

    static func windowStart(days: Int = windowDays, now: Date = .now, calendar: Calendar = .current) -> Date {
        guard days > 0 else { return .distantPast }
        return calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// Photos eligible for Vision analysis that have not been analysed yet.
    var pendingAnalysisCount: Int { analysisCandidates().count }
    var analyzedCount: Int { assets.keys.filter { analysis[$0] != nil }.count }

    func update(settings: BucketSettings) -> BucketSet {
        self.settings = settings
        return currentBuckets()
    }

    /// Analyses pending photos until done or the task is cancelled (pause).
    /// Progress counts this run only. Already-analysed photos are skipped, so a
    /// later call resumes where this one stopped.
    func analyze(progress: @Sendable (ScanProgress) -> Void) async -> BucketSet {
        let pending = analysisCandidates()
        for (index, id) in pending.enumerated() {
            if Task.isCancelled { break }
            if let image = client.analysisImage(for: id, maxPixels: 768) {
                let output = await analyzer.analyze(image)
                analysis[id] = output.analysis
                traits.tags[id] = output.tags
                if let print = output.print {
                    prints[id] = print
                    traits.prints[id] = print
                }
            } else {
                // Not on this iPhone: record as analysed with nothing learned.
                analysis[id] = AssetAnalysis(aestheticScore: nil, isUtility: false, sharpness: nil)
            }
            progress(ScanProgress(completed: index + 1, total: pending.count))
        }
        regroup()
        traits.save(to: traitsURL)
        return currentBuckets()
    }

    /// Decided photos that learning has not read yet.
    func unlearnedCount(labels: [String: Bool]) -> Int {
        min(labels.keys.filter { traits.tags[$0] == nil }.count, Self.learnLimit)
    }

    /// Reads what each decided photo shows and how it looks, wherever it is in the
    /// library, so swipes in Today and Months teach as much as recent ones.
    /// Cancellable; finished photos are kept and skipped next time.
    func learn(labels: [String: Bool], prune: Bool = true, progress: @Sendable (ScanProgress) -> Void) async {
        let pending = Array(labels.keys.filter { traits.tags[$0] == nil }.sorted().prefix(Self.learnLimit))
        for (index, id) in pending.enumerated() {
            if Task.isCancelled { break }
            if let image = client.analysisImage(for: id, maxPixels: 512) {
                let found = await analyzer.traits(image)
                traits.tags[id] = found.tags
                if let print = found.print { traits.prints[id] = print }
            } else {
                // Gone or only in iCloud: remember the attempt so it isn't retried every pass.
                traits.tags[id] = [:]
            }
            if (index + 1) % 100 == 0 { traits.save(to: traitsURL) }
            progress(ScanProgress(completed: index + 1, total: pending.count))
        }
        if prune { traits.prune(keeping: Set(labels.keys).union(assets.keys)) }
        traits.save(to: traitsURL)
    }

    func summary(labels: [String: Bool]) -> TasteSummary {
        TasteSummary(labels: labels, tags: traits.tags)
    }

    func resetLearning() {
        traits = TraitStore()
        for (id, print) in prints { traits.prints[id] = print }
        taste = .prior
        maybeDelete = []
        traits.save(to: traitsURL)
    }

    /// Trains on the labels for photos in the window, then snapshots Maybe Delete.
    /// Suggestions only change when this is called.
    func suggestMaybeDelete(labels: [String: Bool]) -> BucketSet {
        let base = currentBuckets()
        let similarExtras = Set(base.similarGroups.flatMap(\.extraIDs))
        let burstExtras = Bucketer.burstExtraIDs(in: Array(assets.values))
        let keepers = Set((base.similarGroups + base.duplicateGroups).flatMap(\.keeperIDs))
        let tallies = SubjectTaste.tallies(labels: labels, tags: traits.tags)
        let traits = traits
        func features(_ asset: ScannedAsset) -> (x: [Double], subject: SubjectTaste.Score) {
            let id = asset.descriptor.id
            let own = labels[id]
            let subject = traits.tags[id].map { SubjectTaste.score($0, tallies: tallies, own: own) }
                ?? SubjectTaste.Score(value: 0, tag: nil)
            var lookalike = 0.0
            if let print = traits.prints[id] {
                lookalike = LookalikeTaste.score(id: id, labeled: labels) { other in
                    traits.prints[other].flatMap { try? print.distance(to: $0) }
                }
            }
            let x = TasteFeature.vector(asset.descriptor, analysis: analysis[id],
                                        isSimilarExtra: similarExtras.contains(id),
                                        isBurstExtra: burstExtras.contains(id),
                                        subject: subject.value, lookalike: lookalike)
            return (x, subject)
        }
        // Every photo in the window is a candidate; unanalysed ones score on the features they have.
        let known = Array(assets.values)
        let examples = known.compactMap { asset -> (x: [Double], y: Double)? in
            labels[asset.descriptor.id].map { (features(asset).x, $0 ? 1 : 0) }
        }
        taste = TasteModel.train(examples)
        maybeDelete = known
            .filter {
                labels[$0.descriptor.id] == nil && !$0.descriptor.isFavorite && !$0.descriptor.isHidden
                    && !keepers.contains($0.descriptor.id)
            }
            .map { asset -> (id: String, p: Double, reason: String) in
                let (x, subject) = features(asset)
                return (asset.descriptor.id, taste.probability(x), reason(taste.strongestReason(x), subject))
            }
            .filter { $0.p >= Self.suggestionThreshold }
            .sorted { $0.p > $1.p }
            .prefix(Self.suggestionLimit)
            .map { ($0.id, $0.reason) }
        return currentBuckets()
    }

    private func reason(_ feature: TasteFeature?, _ subject: SubjectTaste.Score?) -> String {
        if feature == .subject, let tag = subject?.tag {
            return "Like the \(SubjectTaste.displayName(tag)) photos you delete"
        }
        return feature?.reason ?? "Matches what you delete"
    }

    /// Analysed, unlabelled photos spread across the quality range, for a short training deck.
    func trainingCandidates(count: Int, labels: [String: Bool]) -> [String] {
        // Spread across the quality range; without scores, fall back to a spread over time.
        struct Entry {
            var id: String
            var score: Float
            var date: Date
        }
        var pool: [Entry] = []
        for asset in assets.values {
            let d = asset.descriptor
            guard labels[d.id] == nil, !d.isFavorite, !d.isHidden, d.mediaKind == .image else { continue }
            pool.append(Entry(id: d.id, score: analysis[d.id]?.aestheticScore ?? 0, date: d.creationDate ?? .distantPast))
        }
        pool.sort { $0.score == $1.score ? $0.date < $1.date : $0.score < $1.score }
        guard pool.count > count else { return pool.map(\.id) }
        let step = Double(pool.count) / Double(count)
        return (0..<count).map { pool[Int(Double($0) * step)].id }
    }

    func insights() -> LibraryInsights {
        LibraryInsights.make(from: Array(assets.values))
    }

    private func analysisCandidates() -> [String] {
        assets.values
            .filter {
                $0.descriptor.mediaKind == .image && !$0.descriptor.isScreenshot && !$0.descriptor.isHidden
                    && analysis[$0.descriptor.id] == nil
            }
            .sorted { ($0.descriptor.creationDate ?? .distantPast) > ($1.descriptor.creationDate ?? .distantPast) }
            .map(\.descriptor.id)
    }

    private func regroup() {
        let candidates = assets.values.compactMap { asset -> SimilarGrouper.Candidate? in
            guard prints[asset.descriptor.id] != nil, let date = asset.descriptor.creationDate else { return nil }
            return .init(id: asset.descriptor.id, date: date)
        }
        let prints = prints
        similar = SimilarGrouper.groups(candidates) { lhs, rhs in
            guard let l = prints[lhs], let r = prints[rhs] else { return nil }
            return try? l.distance(to: r)
        }
    }

    private func currentBuckets() -> BucketSet {
        Bucketer.buckets(for: Array(assets.values), analysis: analysis, similar: similar,
                         maybeDelete: maybeDelete, settings: settings)
    }

    func scan(since: Date, progress: @Sendable (ScanProgress) -> Void) -> BucketSet {
        var fresh: [String: ScannedAsset] = [:]
        client.enumerateAssets(since: since) { descriptor, index, total in
            if let scanned = sized(descriptor) { fresh[descriptor.id] = scanned }
            let done = index + 1
            if done == total || done % 50 == 0 {
                progress(ScanProgress(completed: done, total: total))
            }
        }
        assets = fresh
        regroup()
        return currentBuckets()
    }

    /// Applies an incremental change. Returns nil when a full rescan is needed.
    func apply(_ delta: LibraryDelta) -> BucketSet? {
        switch delta {
        case .reload:
            return nil
        case let .incremental(removed, upserted):
            for id in removed {
                assets[id] = nil
                analysis[id] = nil
                prints[id] = nil
            }
            for descriptor in upserted {
                assets[descriptor.id] = sized(descriptor)
            }
            if !removed.isEmpty { regroup() }
            return currentBuckets()
        }
    }

    private func sized(_ descriptor: any AssetDescriptor) -> ScannedAsset? {
        guard let size = sizer.size(of: descriptor) else { return nil }
        return ScannedAsset(descriptor: descriptor, size: size)
    }
}
