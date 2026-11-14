import Foundation
import Testing
@testable import Pictr

@Suite struct SubjectTasteTests {
    // Five food photos deleted, five dog photos kept.
    private let labels: [String: Bool] = Dictionary(uniqueKeysWithValues:
        (0..<5).map { ("food\($0)", true) } + (0..<5).map { ("dog\($0)", false) })
    private let tags: [String: SubjectTags] = Dictionary(uniqueKeysWithValues:
        (0..<5).map { ("food\($0)", ["food": 0.9]) } + (0..<5).map { ("dog\($0)", ["dog": 0.8, "grass": 0.2]) })

    @Test func talliesWeightByConfidenceAndSkipWeakTags() {
        let tallies = SubjectTaste.tallies(labels: labels, tags: tags)
        #expect(abs(tallies["food"]!.deletes - 4.5) < 1e-6)
        #expect(tallies["food"]!.keeps == 0)
        #expect(abs(tallies["dog"]!.keeps - 4.0) < 1e-6)
        #expect(tallies["grass"] == nil) // 0.2 is below the confidence floor
    }

    @Test func subjectYouDeleteScoresPositiveWithItsName() {
        let tallies = SubjectTaste.tallies(labels: labels, tags: tags)
        let food = SubjectTaste.score(["food": 0.7], tallies: tallies)
        let dog = SubjectTaste.score(["dog": 0.7], tallies: tallies)
        #expect(food.value > 0.5)
        #expect(food.tag == "food")
        #expect(dog.value < -0.5)
        #expect(dog.tag == nil)
    }

    @Test func unknownOrThinEvidenceScoresZero() {
        let tallies = SubjectTaste.tallies(labels: ["a": true, "b": true], tags: ["a": ["cat": 0.9], "b": ["cat": 0.9]])
        #expect(SubjectTaste.score(["cat": 0.9], tallies: tallies).value == 0) // 1.8 < 3 photos of evidence
        #expect(SubjectTaste.score(["car": 0.9], tallies: tallies).value == 0)
        #expect(SubjectTaste.score([:], tallies: tallies) == .init(value: 0, tag: nil))
    }

    @Test func leaveOneOutRemovesTheTrainingPhotosOwnVote() {
        // 4.5 of evidence; minus its own 0.9 still clears the floor of 3.
        let small = Dictionary(uniqueKeysWithValues: (0..<5).map { ("f\($0)", true) })
        let smallTags = Dictionary(uniqueKeysWithValues: (0..<5).map { ("f\($0)", ["food": 0.9] as SubjectTags) })
        let tallies = SubjectTaste.tallies(labels: small, tags: smallTags)
        #expect(SubjectTaste.score(["food": 0.9], tallies: tallies).value > 0)
        #expect(SubjectTaste.score(["food": 0.9], tallies: tallies, own: true).value > 0)
        let three = SubjectTaste.tallies(labels: ["f0": true, "f1": true, "f2": true, "f3": true], tags: [
            "f0": ["food": 0.9], "f1": ["food": 0.9], "f2": ["food": 0.9], "f3": ["food": 0.5]])
        // 3.2 total; minus own 0.5 leaves 2.7, under the floor.
        #expect(SubjectTaste.score(["food": 0.5], tallies: three, own: true).value == 0)
    }

    @Test func summaryListsWhatYouDeleteAndKeep() {
        let summary = TasteSummary(labels: labels, tags: tags)
        #expect(summary.deletes.map(\.name) == ["food"])
        #expect(summary.keeps.map(\.name) == ["dog"])
        #expect(summary.labelCount == 10)
        #expect(summary.analyzedLabelCount == 10)
    }

    @Test func displayNameIsReadable() {
        #expect(SubjectTaste.displayName("sport_car") == "sport car")
    }
}

@Suite struct LookalikeTasteTests {
    private let labeled: [String: Bool] = ["d1": true, "d2": true, "d3": true, "k1": false, "far": false]
    private let distances: [String: Double] = ["d1": 0.1, "d2": 0.2, "d3": 0.25, "k1": 0.5, "far": 0.9]

    @Test func nearDeletesVoteForDelete() {
        let score = LookalikeTaste.score(id: "x", labeled: labeled) { distances[$0] }
        #expect(score > 0.6)
    }

    @Test func farPhotosDontVote() {
        let score = LookalikeTaste.score(id: "x", labeled: ["far": false]) { distances[$0] }
        #expect(score == 0)
    }

    @Test func excludesItself() {
        let score = LookalikeTaste.score(id: "d1", labeled: ["d1": true]) { _ in 0 }
        #expect(score == 0)
    }

    @Test func oneNeighborCountsLessThanThree() {
        let one = LookalikeTaste.score(id: "x", labeled: ["d1": true]) { distances[$0] }
        let three = LookalikeTaste.score(id: "x", labeled: ["d1": true, "d2": true, "d3": true]) { distances[$0] }
        #expect(one > 0 && one < three)
        #expect(abs(three - 1) < 1e-9)
    }

    @Test func nearKeepsVoteForKeep() {
        let score = LookalikeTaste.score(id: "x", labeled: ["k1": false, "k2": false, "k3": false]) { _ in 0.1 }
        #expect(score < -0.9)
    }
}
