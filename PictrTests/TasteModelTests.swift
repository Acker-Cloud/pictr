import Foundation
import Testing
@testable import Pictr

@Suite struct TasteModelTests {
    private func x(_ set: [TasteFeature: Double]) -> [Double] {
        TasteFeature.allCases.map { set[$0] ?? 0 }
    }

    @Test func priorRanksJunkAboveAGoodPhoto() {
        let junk = x([.utility: 1, .lowQuality: 0.8])
        let good = x([:])
        #expect(TasteModel.prior.probability(junk) > 0.6)
        #expect(TasteModel.prior.probability(good) < 0.1)
    }

    @Test func reasonIsTheStrongestPush() {
        let reason = TasteModel.prior.strongestReason(x([.utility: 1, .lowQuality: 0.2]))
        #expect(reason == .utility)
        #expect(TasteModel.prior.strongestReason(x([:])) == nil)
    }

    @Test func learnsThatThisUserKeepsScreenshots() {
        // Prior says screenshots lean deletable; this user keeps every one.
        let shot = x([.screenshot: 1, .lowQuality: 0.3])
        let examples = Array(repeating: (x: shot, y: 0.0), count: 30)
            + Array(repeating: (x: x([.soft: 1, .lowQuality: 0.6]), y: 1.0), count: 30)
        let model = TasteModel.train(examples)
        #expect(model.probability(shot) < TasteModel.prior.probability(shot))
        #expect(model.trainedOn == 60)
    }

    @Test func learnsToDeleteSomethingThePriorIgnores() {
        let longVideo = x([.video: 1, .longVideo: 1])
        let before = TasteModel.prior.probability(longVideo)
        let model = TasteModel.train(Array(repeating: (x: longVideo, y: 1.0), count: 40))
        #expect(model.probability(longVideo) > before + 0.2)
    }

    @Test func noLabelsMeansPrior() {
        #expect(TasteModel.train([]) == TasteModel.prior)
    }

    @Test func featureVectorScalesInputs() {
        let asset = FakeAsset(id: "a", creationDate: Date(timeIntervalSince1970: 0), isScreenshot: true,
                              pixelWidth: 4000, pixelHeight: 3000)
        let v = TasteFeature.vector(asset, analysis: .init(aestheticScore: -1, isUtility: true, sharpness: 9),
                                    isSimilarExtra: true, isBurstExtra: false,
                                    now: Date(timeIntervalSince1970: 86_400 * 1000))
        #expect(v.allSatisfy { (0...1).contains($0) })
        #expect(v[TasteFeature.lowQuality.rawValue] == 1)
        #expect(v[TasteFeature.screenshot.rawValue] == 1)
        #expect(v[TasteFeature.similarExtra.rawValue] == 1)
        #expect(v[TasteFeature.lowResolution.rawValue] < 0.1)
    }
}
