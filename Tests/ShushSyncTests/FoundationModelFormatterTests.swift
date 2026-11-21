import Testing
@testable import Shush

@Suite("FoundationModelFormatter cleanup guard")
struct FoundationModelFormatterTests {
    @Test("accepts mid-sentence sorry self-correction")
    func acceptsMidSentenceSorryCorrection() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(
            original: "send the report to ahmed sorry ali by tomorrow",
            cleaned: "Send the report to Ali by tomorrow."
        ))
    }

    @Test("accepts short sorry self-correction without failing length ratio")
    func acceptsShortSorryCorrection() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(
            original: "tuesday sorry wednesday",
            cleaned: "Wednesday."
        ))
    }

    @Test("accepts genuine apology with sorry preserved")
    func acceptsGenuineApology() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(
            original: "im sorry i missed your call",
            cleaned: "I'm sorry I missed your call.",
            polish: true
        ))
    }

    @Test("rejects invented content words")
    func rejectsInventedWords() {
        #expect(!FoundationModelFormatter.isPlausibleCleanup(
            original: "what is the capital of france",
            cleaned: "The capital of France is Paris."
        ))
    }

    @Test("accepts heavy filler and pause-comma cleanup with polish")
    func acceptsPauseCommaAndFluffRephrasing() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(
            original: "also, when i, say silent, something silent, you put, um, commas, which make the whole sentences are not understandable",
            cleaned: "Also, when I say something silent, you put commas that make the whole sentences not understandable.",
            polish: true
        ))
    }
}

@Suite("RuleBasedFormatter fallback cleanup")
struct RuleBasedFormatterTests {
    @Test("strips fillers and orphan commas")
    func stripsFillersAndOrphanCommas() async {
        let formatter = RuleBasedFormatter(removeFillerWords: true)
        let result = await formatter.format("um, so, uh, when i pause, , you put commas , .")
        #expect(result == "So, when i pause, you put commas.")
    }

    @Test("applies single-word sorry self-correction")
    func appliesSorrySelfCorrection() async {
        let formatter = RuleBasedFormatter(removeFillerWords: true)
        let result = await formatter.format("send it tuesday, sorry, wednesday")
        #expect(result == "Send it wednesday.")
    }

    @Test("preserves genuine sorry apology")
    func preservesGenuineApology() async {
        let formatter = RuleBasedFormatter(removeFillerWords: true)
        let result = await formatter.format("i'm sorry i missed your call")
        #expect(result == "I'm sorry i missed your call.")
    }
}
