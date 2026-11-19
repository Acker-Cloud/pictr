import Foundation
import Observation

@MainActor
@Observable
final class LibraryModel {
    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
        case ready
    }

    private(set) var authState: AuthState
    private(set) var phase: Phase = .idle
    private(set) var buckets: BucketSet = .empty
    private(set) var ledger = SpaceLedger()
    private(set) var isDeleting = false
    var deleteError: String?

    enum AnalysisState: Equatable {
        case idle
        case running(ScanProgress)
    }

    private(set) var analysisState: AnalysisState = .idle
    private(set) var analyzedCount = 0
    private(set) var pendingAnalysisCount = 0

    /// Cleanup rules. Persisted; changing the window rescans, anything else rebuckets.
    var settings: BucketSettings {
        didSet {
            guard settings != oldValue else { return }
            Self.save(settings)
            let rescan = settings.windowDays != oldValue.windowDays
            Task {
                if rescan {
                    await scan()
                } else {
                    buckets = await scanner.update(settings: settings)
                }
            }
        }
    }

    /// Labels the current Maybe Delete was trained on. Nil until first update.
    private(set) var tasteTrainedOn: Int?
    /// Reading decided photos before an update. Nil when not learning.
    private(set) var learning: ScanProgress?
    private(set) var tasteSummary: TasteSummary = .empty
    @ObservationIgnored private var learnTask: Task<Void, Never>?
    /// Bucket selections survive leaving and reopening a bucket.
    var selections: [BucketKind: Set<String>] = [:]

    /// Favorite flags changed in Pictr, or read fresh from Photos, since screens loaded their
    /// items. Decks and grids hold snapshots, and a favorite must never be queued, so they ask
    /// `isFavorite(_:)` instead of trusting the snapshot.
    private(set) var knownFavorites: [String: Bool] = [:]

    func isFavorite(_ item: ReviewItem) -> Bool { knownFavorites[item.id] ?? item.isFavorite }

    /// The only way Pictr changes a favorite, so every open screen sees it.
    func setFavorite(_ isFavorite: Bool, id: String) async throws {
        try await client.setFavorite(isFavorite, id: id)
        knownFavorites[id] = isFavorite
    }

    /// Photos is the truth: a favorite changed anywhere, in Pictr or in Photos, replaces what
    /// was remembered. Only favorites and IDs already remembered are kept, so a big sync
    /// doesn't fill this up.
    private func noteFavorites(from delta: LibraryDelta) async {
        switch delta {
        case let .incremental(_, upserted):
            for asset in upserted where asset.isFavorite || knownFavorites[asset.id] != nil {
                knownFavorites[asset.id] = asset.isFavorite
            }
        case .reload:
            let ids = Array(knownFavorites.keys)
            guard !ids.isEmpty else { return }
            let client = client
            let fresh = await Task.detached(priority: .utility) { client.reviewItems(ids: ids) }.value
            for item in fresh { knownFavorites[item.id] = item.isFavorite }
        }
    }

    /// Asks Photos directly and remembers the answer.
    func refreshFavorite(id: String) async -> Bool {
        let client = client
        let value = await Task.detached(priority: .userInitiated) {
            client.reviewItems(ids: [id]).first?.isFavorite ?? false
        }.value
        knownFavorites[id] = value
        return value
    }

    /// Reads any decided photos not seen yet, then rebuilds Maybe Delete.
    /// Stopping keeps what was read and still updates from it.
    func updateSuggestions(labels: [String: Bool]) async {
        // `learning` is set before the first await, so a second tap can't start a second pass.
        guard learnTask == nil, learning == nil else { return }
        learning = ScanProgress(completed: 0, total: 0)
        learning = ScanProgress(completed: 0, total: await scanner.unlearnedCount(labels: labels))
        let task = Task { [weak self] in
            guard let self else { return }
            await scanner.learn(labels: labels) { progress in
                Task { @MainActor [weak self] in
                    guard self?.learning != nil else { return }
                    self?.learning = progress
                }
            }
        }
        learnTask = task
        await task.value
        learning = nil
        learnTask = nil
        buckets = await scanner.suggestMaybeDelete(labels: labels)
        tasteTrainedOn = await scanner.taste.trainedOn
        tasteSummary = await scanner.summary(labels: labels)
    }

    func stopLearning() {
        learnTask?.cancel()
    }

    func refreshTasteSummary(labels: [String: Bool]) async {
        tasteSummary = await scanner.summary(labels: labels)
    }

    func resetLearning(labels: [String: Bool]) async {
        await scanner.resetLearning()
        buckets = await scanner.suggestMaybeDelete(labels: labels)
        tasteTrainedOn = nil
        tasteSummary = await scanner.summary(labels: labels)
    }

    func insights() async -> LibraryInsights {
        await scanner.insights()
    }

    func trainingItems(labels: [String: Bool], count: Int = 24) async -> [ReviewItem] {
        let ids = await scanner.trainingCandidates(count: count, labels: labels)
        let client = client
        return await Task.detached(priority: .userInitiated) { client.reviewItems(ids: ids) }.value
    }

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    private static let settingsKey = "bucketSettings"

    private static func loadSettings() -> BucketSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(BucketSettings.self, from: data)
        else { return BucketSettings() }
        return settings
    }

    private static func save(_ settings: BucketSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    @ObservationIgnored let client: any PhotoLibraryClient
    @ObservationIgnored private let scanner: LibraryScanner
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var rescanPending = false

    init(client: any PhotoLibraryClient, sizer: any SizeProvider = .standard) {
        self.client = client
        self.scanner = LibraryScanner(client: client, sizer: sizer, traitsURL: TraitStore.defaultURL)
        self.authState = client.authorizationState()
        self.settings = Self.loadSettings()
    }

    /// Runs Vision over photos not yet analysed. Pausing keeps what's done.
    func startAnalysis() {
        guard analysisTask == nil else { return }
        analysisState = .running(ScanProgress(completed: 0, total: pendingAnalysisCount))
        analysisTask = Task { [weak self] in
            guard let self else { return }
            let updated = await scanner.analyze { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .running = self.analysisState else { return }
                    self.analysisState = .running(progress)
                }
            }
            buckets = updated
            analysisState = .idle
            analysisTask = nil
            await refreshAnalysisCounts()
        }
    }

    func pauseAnalysis() {
        analysisTask?.cancel()
    }

    private func refreshAnalysisCounts() async {
        analyzedCount = await scanner.analyzedCount
        pendingAnalysisCount = await scanner.pendingAnalysisCount
    }

    var hasAccess: Bool { authState == .authorized || authState == .limited }


    func start() async {
        guard !started else { return }
        started = true
        authState = client.authorizationState()
        if hasAccess { await scan() }
    }

    func requestAccess() async {
        authState = await client.requestAuthorization()
        if hasAccess { await scan() }
    }

    /// Re-reads authorization, e.g. after returning from Settings or the limited picker.
    func refreshAccess() async {
        let state = client.authorizationState()
        guard state != authState else { return }
        authState = state
        if hasAccess { await scan() }
    }

    func scan() async {
        if case .scanning = phase {
            rescanPending = true
            return
        }
        repeat {
            rescanPending = false
            phase = .scanning(ScanProgress(completed: 0, total: 0))
            let since = LibraryScanner.windowStart(days: settings.windowDays)
            _ = await scanner.update(settings: settings)
            buckets = await scanner.scan(since: since) { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .scanning = self.phase else { return }
                    self.phase = .scanning(progress)
                }
            }
        } while rescanPending
        phase = .ready
        await refreshAnalysisCounts()
        observeChanges()
    }

    private func observeChanges() {
        guard !observing else { return }
        observing = true
        Task { [weak self, changes = client.changes] in
            for await delta in changes {
                guard let self else { return }
                await self.noteFavorites(from: delta)
                if let updated = await self.scanner.apply(delta) {
                    self.buckets = updated
                } else {
                    await self.scan()
                }
            }
        }
    }

    /// One system-confirmed batch. The bucket list updates from the change observer.
    @discardableResult
    /// Deletes what is still queued once learning has read it, after Apple's confirmation.
    /// Favorites are never deleted, however they were queued; they are noted in
    /// `knownFavorites` so the caller can take them out of the queue.
    func delete(_ members: [BucketMember], stillQueued: () -> Set<String>) async -> DeleteOutcome? {
        guard !members.isEmpty, !isDeleting else { return nil }
        isDeleting = true
        defer { isDeleting = false }
        // Deleted photos can't be read later; capture what learning needs first.
        await scanner.learn(labels: Dictionary(members.map { ($0.id, true) }, uniquingKeysWith: { a, _ in a }),
                            prune: false) { _ in }
        // That can take a while. Anything taken back or made a favorite meanwhile stays.
        let client = client
        let ids = members.map(\.id)
        let favorites = await Task.detached(priority: .userInitiated) {
            Set(client.reviewItems(ids: ids).filter(\.isFavorite).map(\.id))
        }.value
        for id in favorites { knownFavorites[id] = true }
        let queued = stillQueued()
        let members = members.filter { queued.contains($0.id) && !favorites.contains($0.id) }
        guard !members.isEmpty else { return .deleted([]) }
        ledger.queue(members)
        do {
            let outcome = try await client.delete(ids: members.map(\.id))
            ledger.finish(outcome)
            return outcome
        } catch {
            ledger.fail()
            deleteError = error.localizedDescription
            return nil
        }
    }
}
