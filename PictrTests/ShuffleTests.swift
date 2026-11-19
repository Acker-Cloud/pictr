import Testing
@testable import Pictr

/// SplitMix64: deterministic, so a shuffle test can't flake.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let library = (0..<100).map { "p\($0)" }

@Suite struct ShuffleTests {
    @Test func picksOnlyUndecidedWithoutRepeats() {
        var generator = SeededGenerator(state: 7)
        let decided = Set(library.prefix(90))
        let picked = Shuffle.pick(library, excluding: decided, count: 25, using: &generator)
        #expect(picked.count == 10)
        #expect(Set(picked).count == 10)
        #expect(Set(picked).isDisjoint(with: decided))
    }

    @Test func respectsTheCount() {
        var generator = SeededGenerator(state: 42)
        let picked = Shuffle.pick(library, excluding: [], count: 5, using: &generator)
        #expect(picked.count == 5)
        #expect(Set(picked).count == 5)
    }

    @Test func repeatedIDsCountOnce() {
        var generator = SeededGenerator(state: 1)
        #expect(Shuffle.pick(["a", "a", "a"], excluding: [], count: 5, using: &generator) == ["a"])
    }

    @Test func spreadsAcrossTheLibrary() {
        var generator = SeededGenerator(state: 3)
        let picked = Shuffle.pick(library, excluding: [], count: 20, using: &generator)
        #expect(picked != Array(library.prefix(20)))
    }

    @Test func nothingLeftGivesNothing() {
        var generator = SeededGenerator(state: 9)
        #expect(Shuffle.pick(library, excluding: Set(library), count: 25, using: &generator).isEmpty)
        #expect(Shuffle.pick(library, excluding: [], count: 0, using: &generator).isEmpty)
    }
}
