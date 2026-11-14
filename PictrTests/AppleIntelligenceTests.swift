import Testing
@testable import Pictr

@Suite struct AppleIntelligencePromptTests {
    @Test func promptCarriesOnlyTheFacts() {
        let facts = TasteSummary(deletes: [.init(name: "food", deletes: 9, keeps: 1)],
                                 keeps: [], labelCount: 40, analyzedLabelCount: 38)
        let prompt = AppleIntelligence.prompt(facts)
        #expect(prompt.contains("Decisions so far: 40."))
        #expect(prompt.contains("food (9 deleted, 1 kept)"))
        #expect(prompt.contains("Subjects mostly kept: none yet."))
    }
}
