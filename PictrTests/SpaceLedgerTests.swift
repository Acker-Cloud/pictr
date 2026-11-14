import Testing
@testable import Pictr

@Suite struct SpaceLedgerTests {
    private let a = BucketMember(id: "a", size: AssetSize(bytes: 100, isEstimated: false), availability: .onDevice)
    private let b = BucketMember(id: "b", size: AssetSize(bytes: 50, isEstimated: true), availability: .cloudOnly)

    @Test func confirmedDeleteMovesQueuedToRecentlyDeleted() {
        var ledger = SpaceLedger()
        ledger.queue([a, b])
        #expect(ledger.queuedBytes == 150)
        ledger.finish(.deleted(["a", "b"]))
        #expect(ledger.queuedBytes == 0)
        #expect(ledger.movedBytes == 150)
        #expect(ledger.movedCount == 2)
        #expect(ledger.movedCloudOnlyBytes == 50)
    }

    @Test func onlySubmittedAssetsCountAsMoved() {
        var ledger = SpaceLedger()
        ledger.queue([a, b])
        ledger.finish(.deleted(["a"]))
        #expect(ledger.movedBytes == 100)
        #expect(ledger.movedCount == 1)
        #expect(ledger.movedCloudOnlyBytes == 0)
    }

    @Test func emptySubmissionMovesNothing() {
        var ledger = SpaceLedger()
        ledger.queue([a, b])
        ledger.finish(.deleted([]))
        #expect(ledger.movedBytes == 0)
        #expect(ledger.queuedBytes == 0)
    }

    @Test func cancelLeavesNothingMoved() {
        var ledger = SpaceLedger()
        ledger.queue([a])
        ledger.finish(.cancelled)
        #expect(ledger.queuedBytes == 0)
        #expect(ledger.movedBytes == 0)
    }

    @Test func failureClearsQueue() {
        var ledger = SpaceLedger()
        ledger.queue([a])
        ledger.fail()
        #expect(ledger.queuedBytes == 0)
        #expect(ledger.movedBytes == 0)
    }
}
