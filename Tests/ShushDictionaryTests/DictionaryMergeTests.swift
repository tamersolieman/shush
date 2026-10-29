import Testing
@testable import ShushDictionary

@Suite("Dictionary merge")
struct DictionaryMergeTests {
    @Test("rules from both sides are kept")
    func keepsBoth() {
        let merged = DictionaryEntry.union(
            local: [.term("Anthropic"), .correction(hear: "cloud code", write: "Claude Code")],
            remote: [.term("Vercel")]
        )
        #expect(merged.map(\.write) == ["Anthropic", "Claude Code", "Vercel"])
    }

    @Test("local wins on a rule both sides have, including its enabled state")
    func localWins() {
        var local = DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")
        local.isEnabled = false
        let remote = DictionaryEntry.correction(hear: "Cloud Code ", write: "Claude Code (remote)")
        let merged = DictionaryEntry.union(local: [local], remote: [remote])
        #expect(merged == [local])
    }

    @Test("a term and a correction with the same text are different rules")
    func kindsAreDistinct() {
        let merged = DictionaryEntry.union(
            local: [.term("Shush")],
            remote: [.correction(hear: "Shush", write: "Shush")]
        )
        #expect(merged.count == 2)
    }
}
