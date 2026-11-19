import CoreGraphics
import Foundation
import Testing
@testable import Pictr

private final class FakeClient: PhotoLibraryClient, @unchecked Sendable {
    let assets: [FakeAsset]
    let changes: AsyncStream<LibraryDelta>
    init(_ assets: [FakeAsset]) {
        self.assets = assets
        changes = AsyncStream { $0.finish() }
    }
    func authorizationState() -> AuthState { .authorized }
    func requestAuthorization() async -> AuthState { .authorized }
    func enumerateAssets(since: Date, _ body: (any AssetDescriptor, Int, Int) -> Void) {
        for (index, asset) in assets.enumerated() { body(asset, index, assets.count) }
    }
    func delete(ids: [String]) async throws -> DeleteOutcome { .deleted(Set(ids)) }
    func setFavorite(_ isFavorite: Bool, id: String) async throws {}
    func earliestAssetDate() -> Date? { nil }
    func reviewItems(in windows: [DateInterval]) -> [ReviewItem] { [] }
    func reviewItems(ids: [String]) -> [ReviewItem] { [] }
    func assetIndex() -> [AssetStamp] { [] }
    func members(for ids: [String]) -> [BucketMember] { [] }
    func analysisImage(for id: String, maxPixels: Int) -> CGImage? { nil }
    func exportOriginal(id: String) async throws -> URL { throw CancellationError() }
}

private func exact(_ bytes: Int64) -> [ResourceRecord] {
    [ResourceRecord(kind: .photo, byteCount: bytes, isLocallyAvailable: true)]
}

@Suite struct LibraryScannerTests {
    @Test func scanSizesEveryAssetAndReportsFinalProgress() async {
        let client = FakeClient([
            FakeAsset(id: "s1", isScreenshot: true, resources: exact(10)),
            FakeAsset(id: "s2", isScreenshot: true, pixelWidth: 100, pixelHeight: 100),
        ])
        let scanner = LibraryScanner(client: client)
        let last = Locked<ScanProgress?>(nil)
        let set = await scanner.scan(since: .distantPast) { last.value = $0 }
        #expect(set[.screenshots].totalBytes == 10 + 2_500)
        #expect(set[.screenshots].hasEstimates)
        #expect(last.value == ScanProgress(completed: 2, total: 2))
    }

    @Test func incrementalDeltaRemovesAndUpserts() async {
        let client = FakeClient([
            FakeAsset(id: "s1", isScreenshot: true, resources: exact(10)),
            FakeAsset(id: "s2", isScreenshot: true, resources: exact(20)),
        ])
        let scanner = LibraryScanner(client: client)
        _ = await scanner.scan(since: .distantPast) { _ in }

        let favorited = FakeAsset(id: "s2", isScreenshot: true, isFavorite: true, resources: exact(20))
        let added = FakeAsset(id: "s3", isScreenshot: true, resources: exact(30))
        let set = await scanner.apply(.incremental(removed: ["s1"], upserted: [favorited, added]))
        #expect(set.map { Set($0[.screenshots].members.map(\.id)) } == ["s3"])
        #expect(set?[.screenshots].totalBytes == 30)
    }

    @Test func maybeDeleteLearnsFromSwipesAndExplainsWhy() async {
        var assets = (0..<20).map { FakeAsset(id: "shot\($0)", isScreenshot: true, resources: exact(10)) }
        assets += (0..<20).map { FakeAsset(id: "photo\($0)", resources: exact(10)) }
        assets.append(FakeAsset(id: "newShot", isScreenshot: true, resources: exact(10)))
        assets.append(FakeAsset(id: "newPhoto", resources: exact(10)))
        assets.append(FakeAsset(id: "favShot", isScreenshot: true, isFavorite: true, resources: exact(10)))
        let scanner = LibraryScanner(client: FakeClient(assets))
        _ = await scanner.scan(since: .distantPast) { _ in }

        var labels: [String: Bool] = [:]
        for i in 0..<20 { labels["shot\(i)"] = true; labels["photo\(i)"] = false }
        let set = await scanner.suggestMaybeDelete(labels: labels)

        let ids = Set(set[.maybeDelete].members.map(\.id))
        #expect(ids == ["newShot"])
        #expect(set.reasons["newShot"] == TasteFeature.screenshot.reason)
        #expect(await scanner.taste.trainedOn == 40)
    }

    @Test func trainingCandidatesSkipLabelledFavoritesAndVideos() async {
        let scanner = LibraryScanner(client: FakeClient([
            FakeAsset(id: "a", resources: exact(1)), FakeAsset(id: "b", resources: exact(1)),
            FakeAsset(id: "fav", isFavorite: true, resources: exact(1)),
            FakeAsset(id: "clip", mediaKind: .video, resources: exact(1)),
            FakeAsset(id: "done", resources: exact(1)),
        ]))
        _ = await scanner.scan(since: .distantPast) { _ in }
        let ids = await scanner.trainingCandidates(count: 10, labels: ["done": false])
        #expect(Set(ids) == ["a", "b"])
    }

    @Test func reloadAsksForRescan() async {
        let scanner = LibraryScanner(client: FakeClient([]))
        #expect(await scanner.apply(.reload) == nil)
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

@Suite struct TraitStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "traits-\(UUID().uuidString).json")
    }

    @Test func missingFileStartsEmpty() {
        #expect(TraitStore.load(from: tempURL())?.tags.isEmpty == true)
    }

    @Test func savedStoreReadsBack() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var store = TraitStore()
        store.tags["a"] = ["dog": 0.9]
        store.save(to: url)
        #expect(TraitStore.load(from: url)?.tags["a"] == ["dog": 0.9])
    }

    @Test func unreadableStoreIsNotTreatedAsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var store = TraitStore()
        store.tags["a"] = ["dog": 0.9]
        store.save(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path(percentEncoded: false))
        #expect(TraitStore.load(from: url) == nil)
    }

    @Test func mergeAddsSavedEntriesAndKeepsNewerOnes() {
        var saved = TraitStore()
        saved.tags = ["a": ["dog": 0.9], "b": ["cat": 0.5]]
        var current = TraitStore()
        current.tags = ["b": ["cat": 0.8]]
        current.merge(saved)
        #expect(current.tags == ["a": ["dog": 0.9], "b": ["cat": 0.8]])
    }
}
