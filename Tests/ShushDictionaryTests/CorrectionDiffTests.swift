import Testing
@testable import ShushDictionary

@Suite("Correction diff")
struct CorrectionDiffTests {
    @Test("identical strings are not a correction")
    func identical() {
        #expect(CorrectionDiff.detect(original: "hello world", current: "hello world") == nil)
    }

    @Test("continued dictation (append) is not a correction")
    func prefixAppend() {
        #expect(CorrectionDiff.detect(original: "cloud code", current: "cloud code is great") == nil)
    }

    @Test("pure insertion with nothing replaced is not a correction")
    func pureInsertion() {
        #expect(CorrectionDiff.detect(original: "the team", current: "the whole team") == nil)
    }

    @Test("pure deletion with nothing to map to is not a correction")
    func pureDeletion() {
        #expect(CorrectionDiff.detect(original: "the whole team", current: "the team") == nil)
    }

    @Test("whitespace/punctuation-only diff is not a correction")
    func punctuationOnly() {
        #expect(CorrectionDiff.detect(original: "hello world", current: "hello, world") == nil)
    }

    @Test("an oversized word-count diff is rejected")
    func tooManyWords() {
        let original = "cloud code is a great tool"
        let current = "one two three four five six is a great tool"
        #expect(CorrectionDiff.detect(original: original, current: current) == nil)
    }

    @Test("an oversized character-length diff is rejected")
    func tooManyCharacters() {
        let longWord = String(repeating: "x", count: 41)
        #expect(CorrectionDiff.detect(original: "hello \(longWord) there", current: "hello y there") == nil)
    }

    @Test("a case-only correction is accepted")
    func caseOnly() {
        let result = CorrectionDiff.detect(original: "I use claude daily", current: "I use Claude daily")
        #expect(result == CorrectionDiff.Correction(hear: "claude", write: "Claude"))
    }

    @Test("a clean single-word substitution is accepted")
    func singleWord() {
        let result = CorrectionDiff.detect(original: "I used cloud code yesterday", current: "I used Anthropic yesterday")
        #expect(result == CorrectionDiff.Correction(hear: "cloud code", write: "Anthropic"))
    }

    @Test("a clean short-phrase substitution is accepted")
    func shortPhrase() {
        let result = CorrectionDiff.detect(original: "I used cloud code yesterday", current: "I used Claude Code yesterday")
        #expect(result == CorrectionDiff.Correction(hear: "cloud code", write: "Claude Code"))
    }
}
